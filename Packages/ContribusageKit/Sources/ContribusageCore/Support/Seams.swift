import Foundation

/// The seams of SPEC §10.6. Live implementations sit in `Support/Live`, fakes in `ContribusageTestSupport`.

/// Not named `Clock`: avoids clashing with `Swift.Clock`.
public protocol TimeSource: Sendable {
    var now: Date { get }
}

public struct ProcessRequest: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let workingDirectory: URL
    /// `nil` inherits the app's environment.
    public let environment: [String: String]?
    public let timeout: Duration

    public init(
        executable: URL, arguments: [String], workingDirectory: URL, environment: [String: String]?,
        timeout: Duration
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeout = timeout
    }
}

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol ProcessRunning: Sendable {
    func run(_ request: ProcessRequest) async throws -> ProcessResult
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Holds only the app's own secrets (the GitHub token, FR-16), never another tool's (SPEC §2).
public protocol SecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ key: String, value: String) throws
    /// Deleting a missing key succeeds.
    func delete(_ key: String) throws
}

public protocol FileEvents: Sendable {
    /// Batches of changed file URLs under `roots`. Cancelling the consumer stops the watching.
    func changes(in roots: [URL], debounce: Duration) -> AsyncStream<Set<URL>>
}

/// Every file a provider's activity source lists or reads goes through here, so the conformance suite can check that it
/// stays inside its declared roots (SPEC §16.4).
public protocol FileReading: Sendable {
    /// Everything under `folder`, recursively; `nil` when it cannot be listed.
    func enumerator(at folder: URL) -> FileManager.DirectoryEnumerator?
    func handle(forReadingFrom file: URL) throws -> FileHandle
    func contents(of file: URL) throws -> Data
}
