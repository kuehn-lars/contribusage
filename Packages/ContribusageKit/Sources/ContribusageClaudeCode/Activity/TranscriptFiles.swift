import Foundation

/// Where Claude Code keeps its transcripts (SPEC §8.3.1, FR-22) and which of them count (FR-28).
public enum TranscriptFiles {
    /// FR-22 roots in order, without duplicates, whether they exist or not: a root that appears later is watched
    /// already (SPEC §13), and `files(in:excludingProjectOf:)` finds nothing in a missing one. `configDir` is
    /// `CLAUDE_CONFIG_DIR` from the login shell.
    public static func roots(home: URL, configDir: URL?) -> [URL] {
        var roots: [URL] = []
        for base in [configDir, home.appending(path: ".claude"), home.appending(path: ".config/claude")] {
            guard let root = base?.appending(path: "projects", directoryHint: .isDirectory).standardizedFileURL,
                !roots.contains(root)
            else { continue }
            roots.append(root)
        }
        return roots
    }

    /// `**/*.jsonl` under `roots`, without the project directory of `probeFolder`: probes should not persist sessions,
    /// but if one does, it must not count as activity (FR-28).
    public static func files(in roots: [URL], excludingProjectOf probeFolder: URL) -> [URL] {
        // Claude Code names a project directory after the working directory with every character outside
        // `[a-zA-Z0-9]` replaced by `-` (R-3: `/` and spaces both become `-`).
        // A directory URL's path ends in "/", which Claude Code's working directory does not.
        var probePath = probeFolder.path(percentEncoded: false)
        if probePath.hasSuffix("/") { probePath.removeLast() }
        let probeProject = probePath.replacing(/[^a-zA-Z0-9]/, with: "-")
        var files: [URL] = []
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in enumerator {
                if enumerator.level == 1, url.lastPathComponent == probeProject {
                    enumerator.skipDescendants()
                } else if url.pathExtension == "jsonl" {
                    files.append(url)
                }
            }
        }
        return files
    }
}
