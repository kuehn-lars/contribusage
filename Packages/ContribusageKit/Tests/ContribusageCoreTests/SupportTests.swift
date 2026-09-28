import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// SPEC §10.6: every seam has a fake the later tasks build on; these pin the behaviour they rely on.

@Test func fakeTimeSourceMovesOnlyWhenTold() {
    let time = FakeTimeSource(now: Date(timeIntervalSince1970: 1_000))
    #expect(time.now == Date(timeIntervalSince1970: 1_000))
    time.advance(by: .milliseconds(90_500))
    #expect(time.now == Date(timeIntervalSince1970: 1_090.5))
    time.now = Date(timeIntervalSince1970: 5)
    #expect(time.now == Date(timeIntervalSince1970: 5))
}

@Test func fakeProcessRunnerRecordsRequestsAndReturnsTheScriptedResult() async throws {
    let runner = FakeProcessRunner { _ in ProcessResult(exitCode: 0, stdout: "2.0.0 (Claude Code)", stderr: "") }
    let request = ProcessRequest(
        executable: URL(filePath: "/opt/homebrew/bin/claude"),
        arguments: ["--version"],
        workingDirectory: URL(filePath: "/tmp"),
        environment: nil,
        timeout: .seconds(10)
    )
    #expect(try await runner.run(request).stdout == "2.0.0 (Claude Code)")
    #expect(runner.requests == [request])
}

@Test func fakeHTTPTransportRecordsRequestsAndReturnsTheScriptedResponse() async throws {
    let url = URL(string: "https://api.github.com/graphql")!
    let transport = FakeHTTPTransport { request in
        (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
    }
    let (data, response) = try await transport.send(URLRequest(url: url))
    #expect(data == Data("{}".utf8))
    #expect(response.statusCode == 401)
    #expect(transport.requests.map(\.url) == [url])
}

@Test func fakeSecretStoreRoundTrips() throws {
    let store = FakeSecretStore()
    #expect(try store.read("token") == nil)
    try store.write("token", value: "ghp_example")
    #expect(try store.read("token") == "ghp_example")
    try store.delete("token")
    #expect(try store.read("token") == nil)
    try store.delete("token")  // deleting a missing key is not an error, as with the Keychain's "not found"
}

/// SPEC §16.4: "`stop()` releases all file watching (fake `FileEvents` reports zero active streams)".
@Test func fakeFileEventsDeliversToActiveStreamsAndCountsThem() async {
    let events = FakeFileEvents()
    let root = URL(filePath: "/tmp/projects")
    let changed: Set = [root.appending(path: "a.jsonl")]

    let stream = events.changes(in: [root], debounce: .seconds(5))
    #expect(events.activeStreams == 1)

    events.send(changed)
    var iterator = stream.makeAsyncIterator()
    #expect(await iterator.next() == changed)
}

@Test func fakeFileEventsForgetsAStreamWhoseConsumerIsCancelled() async {
    let events = FakeFileEvents()
    let stream = events.changes(in: [], debounce: .zero)
    #expect(events.activeStreams == 1)
    let consumer = Task { for await _ in stream {} }
    consumer.cancel()
    await consumer.value
    #expect(events.activeStreams == 0)
}

/// SPEC §10.7: data lives in `root/providers/<id>/`; deleting a provider's data removes exactly that folder.
@Test func appPathsLayout() {
    let paths = AppPaths(root: URL(filePath: "/tmp/contribusage-test", directoryHint: .isDirectory))
    #expect(paths.providerFolder(.fake).path() == "/tmp/contribusage-test/providers/fake/")
    #expect(AppPaths.live.root.path(percentEncoded: false).hasSuffix("/Library/Application Support/contribusage/"))
}

/// Anything but an HTTP response (a `file:` URL here, offline) is an error, not a crash.
@Test func urlSessionTransportRejectsNonHTTPResponses() async throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "contribusage-\(UUID()).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    await #expect(throws: URLError.self) { try await URLSessionTransport().send(URLRequest(url: file)) }
}
