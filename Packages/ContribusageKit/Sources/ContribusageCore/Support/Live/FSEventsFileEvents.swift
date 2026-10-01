import CoreServices
import Foundation

/// FR-27: one FSEvents stream per `changes(in:debounce:)` call, with file level events and the debounce as its
/// latency, delivered on a utility queue. Batches hold changed files (not folders) by their real path (symlinks
/// in a root resolved). A root may not exist yet; its files are reported once it does. Events FSEvents drops
/// are not reported; the owner's rescan on wake and popover open covers them (SPEC §10.2). A stream FSEvents
/// cannot create or start finishes at once.
public struct FSEventsFileEvents: FileEvents {
    public init() {}

    public func changes(in roots: [URL], debounce: Duration) -> AsyncStream<Set<URL>> {
        let (batches, continuation) = AsyncStream.makeStream(of: Set<URL>.self)
        let sink = Unmanaged.passRetained(Sink(continuation))
        var context = FSEventStreamContext(
            version: 0, info: sink.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        guard
            let created = FSEventStreamCreate(
                nil, Self.callback, &context, roots.map { $0.path(percentEncoded: false) } as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                debounce.timeInterval, FSEventStreamCreateFlags(flags))
        else {
            sink.release()
            continuation.finish()
            return batches
        }
        // Not Sendable; after the start it is used only on its queue.
        nonisolated(unsafe) let stream = created
        let queue = DispatchQueue(label: "contribusage.file-events", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        // On the stream's queue, so no callback runs during or after the teardown.
        continuation.onTermination = { _ in
            queue.async {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                sink.release()
            }
        }
        if !FSEventStreamStart(stream) { continuation.finish() }
        return batches
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        let sink = Unmanaged<Sink>.fromOpaque(info!).takeUnretainedValue()
        let paths = unsafeBitCast(paths, to: NSArray.self)
        let files = (0..<count).filter { flags[$0] & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0 }
            .compactMap { paths[$0] as? String }.map { URL(filePath: $0) }
        if !files.isEmpty { sink.continuation.yield(Set(files)) }
    }
}

private final class Sink: Sendable {
    let continuation: AsyncStream<Set<URL>>.Continuation
    init(_ continuation: AsyncStream<Set<URL>>.Continuation) { self.continuation = continuation }
}
