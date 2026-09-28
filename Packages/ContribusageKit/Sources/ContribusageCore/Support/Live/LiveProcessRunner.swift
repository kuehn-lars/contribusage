import Foundation

/// Runs child processes for every provider (SPEC §8.1.1, FR-7): stdin `/dev/null`, stdout and stderr read
/// concurrently, the timeout sends SIGTERM and SIGKILL 2 s later, as does cancelling the calling task.
/// At most one process runs at a time across all instances (NFR-18); later calls wait their turn.
public struct LiveProcessRunner: ProcessRunning {
    private static let gate = Gate()

    public init() {}

    /// Throws `SourceError.timedOut`, `CancellationError`, or the launch error when the executable cannot start.
    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        try await Self.gate.turn { try await Self.launch(request) }
    }

    private static func launch(_ request: ProcessRequest) async throws -> ProcessResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.currentDirectoryURL = request.workingDirectory
        if let environment = request.environment { process.environment = environment }
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let (exit, exited) = AsyncStream.makeStream(of: Never.self)
        process.terminationHandler = { _ in exited.finish() }
        try process.run()

        // Readers start only after a successful launch: before it, the write ends are still open here.
        // ponytail: a grandchild that keeps the pipes open delays the result until it exits; kill the
        // process group if a tool ever does that.
        async let output = readToEnd(stdout.fileHandleForReading)
        async let errors = readToEnd(stderr.fileHandleForReading)
        let deadline = Task {
            guard (try? await Task.sleep(for: request.timeout)) != nil else { return false }
            stop(process)
            return true
        }
        await withTaskCancellationHandler {
            // Unstructured, so cancellation does not end the wait early (an `AsyncStream` loop would).
            await Task { for await _ in exit {} }.value
        } onCancel: {
            stop(process)
        }
        deadline.cancel()
        let result = ProcessResult(
            exitCode: process.terminationStatus, stdout: String(decoding: await output, as: UTF8.self),
            stderr: String(decoding: await errors, as: UTF8.self))
        try Task.checkCancellation()
        if await deadline.value { throw SourceError.timedOut }
        return result
    }

    /// SIGTERM now, SIGKILL after 2 s if it is still running. Calling it twice is harmless.
    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: handle.readDataToEndOfFile()) }
        }
    }
}

/// A FIFO async lock.
private actor Gate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // ponytail: a cancelled caller still waits for its turn (at most one running process, 32 s), then
    // throws; add cancellable waiters if that delay ever shows.
    private func acquire() async {
        guard busy else {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func turn<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await body()
    }
}
