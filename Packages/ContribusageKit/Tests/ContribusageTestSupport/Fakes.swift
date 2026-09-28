import ContribusageCore
import Foundation
import os

/// Fakes for the seams of SPEC §10.6. Each is thread safe and records what it was asked.

public final class FakeTimeSource: TimeSource {
    private let state: OSAllocatedUnfairLock<Date>

    public init(now: Date) { state = .init(initialState: now) }

    public var now: Date {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    public func advance(by duration: Duration) {
        state.withLock { $0 += duration / .seconds(1) }
    }
}

/// Answers every request with `handler`; a handler that sleeps models a process that never finishes.
public final class FakeProcessRunner: ProcessRunning {
    private let handler: @Sendable (ProcessRequest) async throws -> ProcessResult
    private let recorded = OSAllocatedUnfairLock<[ProcessRequest]>(initialState: [])

    public init(handler: @escaping @Sendable (ProcessRequest) async throws -> ProcessResult) { self.handler = handler }

    public var requests: [ProcessRequest] { recorded.withLock { $0 } }

    public func run(_ request: ProcessRequest) async throws -> ProcessResult {
        recorded.withLock { $0.append(request) }
        return try await handler(request)
    }
}

public final class FakeHTTPTransport: HTTPTransport {
    private let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let recorded = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    public init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    public var requests: [URLRequest] { recorded.withLock { $0 } }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        return try await handler(request)
    }
}

public final class FakeSecretStore: SecretStore {
    private let secrets = OSAllocatedUnfairLock<[String: String]>(initialState: [:])

    public init() {}

    public func read(_ key: String) throws -> String? { secrets.withLock { $0[key] } }
    public func write(_ key: String, value: String) throws { secrets.withLock { $0[key] = value } }
    public func delete(_ key: String) throws { _ = secrets.withLock { $0.removeValue(forKey: key) } }
}

/// `send(_:)` delivers a batch to every open stream; `roots` and `debounce` are ignored.
public final class FakeFileEvents: FileEvents {
    private let continuations = OSAllocatedUnfairLock<[UUID: AsyncStream<Set<URL>>.Continuation]>(initialState: [:])

    public init() {}

    /// Streams not yet terminated; SPEC §16.4 expects zero after a provider's `stop()`.
    public var activeStreams: Int { continuations.withLock { $0.count } }

    public func changes(in roots: [URL], debounce: Duration) -> AsyncStream<Set<URL>> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Set<URL>>.makeStream()
        continuation.onTermination = { [continuations] _ in _ = continuations.withLock { $0.removeValue(forKey: id) } }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    public func send(_ urls: Set<URL>) {
        for continuation in continuations.withLock({ Array($0.values) }) { continuation.yield(urls) }
    }
}
