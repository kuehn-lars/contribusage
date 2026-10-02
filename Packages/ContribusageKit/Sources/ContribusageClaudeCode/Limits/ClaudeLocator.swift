import ContribusageCore
import Foundation

/// Finds the `claude` executable (FR-6). Stateless: the provider caches the result and knows when
/// the cached path stops working (T-2.5).
public struct ClaudeLocator: Sendable {
    public struct Found: Sendable {
        public let executable: URL
        /// `claude --version` output, trimmed.
        public let version: String
        /// The app's environment with PATH from the login shell (SPEC §8.1.1); nil inherits it unchanged.
        /// An npm install is a `#!/usr/bin/env node` script, which fails without it when the app starts from Finder.
        public let environment: [String: String]?
        /// For diagnostics (FR-36) and the Providers tab.
        public let kind: ExecutableKind
    }

    /// For diagnostics (FR-36).
    public enum ExecutableKind: Sendable {
        case machOArm64
        /// x86_64, needs Rosetta.
        case machOIntel
        /// For example the npm shim.
        case script
        case unknown

        /// Reads the file header; symlinks are followed.
        public init(at url: URL) {
            let head = [UInt8](((try? Data(contentsOf: url, options: .alwaysMapped)) ?? Data()).prefix(512))
            func word(_ offset: Int, bigEndian: Bool) -> UInt32? {
                guard head.count >= offset + 4 else { return nil }
                let raw = head.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
                return bigEndian ? UInt32(bigEndian: raw) : UInt32(littleEndian: raw)
            }
            func cpu(_ type: UInt32?) -> Self? {
                switch type {
                case 0x0100_000C: .machOArm64
                case 0x0100_0007: .machOIntel
                default: nil
                }
            }
            if head.starts(with: "#!".utf8) {
                self = .script
            } else if word(0, bigEndian: false) == 0xFEED_FACF {
                self = cpu(word(4, bigEndian: false)) ?? .unknown
            } else if word(0, bigEndian: true) == 0xCAFE_BABE, let count = word(4, bigEndian: true) {
                // Universal: 20-byte slice records after the 8-byte header. Native when one slice is arm64.
                let slices = (0..<min(Int(count), (head.count - 8) / 20)).compactMap {
                    cpu(word(8 + 20 * $0, bigEndian: true))
                }
                self = slices.contains(.machOArm64) ? .machOArm64 : slices.first ?? .unknown
            } else {
                self = .unknown
            }
        }
    }

    private let runner: any ProcessRunning
    private let home: URL
    private let shell: URL

    /// `shell` is the user's login shell, usually `/bin/zsh`.
    public init(runner: any ProcessRunning, home: URL, shell: URL) {
        self.runner = runner
        self.home = home
        self.shell = shell
    }

    /// The first candidate in FR-6 order whose `--version` exits with 0 within 10 s. An invalid
    /// override falls through to the other candidates.
    public func locate(override: URL? = nil) async -> Found? {
        let shell = await loginShell()
        let environment = shell.path.map { ProcessInfo.processInfo.environment.merging(["PATH": $0]) { $1 } }
        let candidates =
            [override, shell.claude].compactMap(\.self) + [
                home.appending(path: ".local/bin/claude"),
                URL(filePath: "/opt/homebrew/bin/claude"),
                home.appending(path: ".npm-global/bin/claude"),
                URL(filePath: "/usr/local/bin/claude"),
            ]
        for candidate in candidates {
            guard let result = try? await run(candidate, ["--version"], environment), result.exitCode == 0 else {
                continue
            }
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return Found(
                executable: candidate, version: version, environment: environment, kind: ExecutableKind(at: candidate))
        }
        return nil
    }

    /// One login shell run for both answers. PATH comes last so that output from profile scripts
    /// only precedes it; the line before counts as `claude` only when it is an absolute path (an
    /// alias prints `alias claude=…`, a miss prints nothing).
    private func loginShell() async -> (claude: URL?, path: String?) {
        guard
            let result = try? await run(shell, ["-lc", #"command -v claude; printf '%s\n' "$PATH""#], nil),
            result.exitCode == 0
        else { return (nil, nil) }
        let lines = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
        let claude = lines.dropLast().last.flatMap { $0.hasPrefix("/") ? URL(filePath: $0) : nil }
        return (claude, lines.last)
    }

    private func run(_ executable: URL, _ arguments: [String], _ environment: [String: String]?) async throws
        -> ProcessResult
    {
        try await runner.run(
            ProcessRequest(
                executable: executable, arguments: arguments, workingDirectory: home, environment: environment,
                timeout: .seconds(10)))
    }
}
