import ContribusageCore
import Foundation
import Testing

private func request(
    _ executable: String, _ arguments: [String] = [], in folder: URL = URL(filePath: "/tmp"),
    timeout: Duration = .seconds(10)
) -> ProcessRequest {
    ProcessRequest(
        executable: URL(filePath: executable), arguments: arguments, workingDirectory: folder, environment: nil,
        timeout: timeout)
}

/// SPEC §16.1 process tests: `LiveProcessRunner` against real system tools (FR-7, NFR-18).
/// Serialized: every runner shares one global gate, so parallel tests would skew the timing checks.
@Suite(.serialized) struct LiveProcessRunnerTests {
    @Test func capturesStdoutAndExitCode() async throws {
        let result = try await LiveProcessRunner().run(request("/bin/echo", ["hello"]))
        #expect(result == ProcessResult(exitCode: 0, stdout: "hello\n", stderr: ""))
        #expect(try await LiveProcessRunner().run(request("/usr/bin/false")).exitCode == 1)
    }

    @Test func capturesStderrAndUsesTheWorkingDirectoryAndEnvironment() async throws {
        let result = try await LiveProcessRunner().run(
            ProcessRequest(
                executable: URL(filePath: "/bin/sh"), arguments: ["-c", "pwd; echo \"$GREETING\" >&2"],
                workingDirectory: URL(filePath: "/usr"), environment: ["GREETING": "hi"], timeout: .seconds(10)))
        #expect(result.stdout == "/usr\n")
        #expect(result.stderr == "hi\n")
    }

    /// Output larger than the pipe buffer on both streams deadlocks a runner that waits for exit before reading.
    @Test func readsLargeOutputOnBothStreamsWithoutDeadlock() async throws {
        let result = try await LiveProcessRunner().run(
            request(
                "/bin/sh", ["-c", "head -c 500000 /dev/zero | tr '\\0' a; head -c 500000 /dev/zero | tr '\\0' b >&2"]))
        #expect(result.stdout.count == 500_000)
        #expect(result.stderr.count == 500_000)
    }

    @Test func stdinIsDevNull() async throws {
        // `cat` waits forever on an inherited or open stdin.
        #expect(try await LiveProcessRunner().run(request("/bin/cat", timeout: .seconds(5))).stdout == "")
    }

    @Test func timeoutThrowsTimedOut() async {
        let start = ContinuousClock.now
        await #expect(throws: SourceError.timedOut) {
            try await LiveProcessRunner().run(request("/bin/sleep", ["10"], timeout: .milliseconds(200)))
        }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func killsAProcessThatIgnoresSIGTERM() async {
        let start = ContinuousClock.now
        await #expect(throws: SourceError.timedOut) {
            try await LiveProcessRunner().run(
                request("/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 10"], timeout: .milliseconds(200)))
        }
        #expect(ContinuousClock.now - start < .seconds(5))  // 0.2 s timeout + 2 s grace, not 10 s
    }

    @Test func cancellationTerminatesTheProcess() async {
        let start = ContinuousClock.now
        let task = Task { try await LiveProcessRunner().run(request("/bin/sleep", ["10"])) }
        try? await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func missingExecutableThrows() async {
        await #expect(throws: (any Error).self) { try await LiveProcessRunner().run(request("/no/such/tool")) }
    }

    /// NFR-18: `mkdir` is atomic, so a second process running at the same time fails to take the lock.
    @Test func runsOneProcessAtATimeAcrossRunners() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = request("/bin/sh", ["-c", "mkdir lock || exit 7; sleep 0.2; rmdir lock"], in: folder)

        let codes = try await withThrowingTaskGroup(of: Int32.self) { group in
            for _ in 0..<3 { group.addTask { try await LiveProcessRunner().run(script).exitCode } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(codes == [0, 0, 0])
    }
}
