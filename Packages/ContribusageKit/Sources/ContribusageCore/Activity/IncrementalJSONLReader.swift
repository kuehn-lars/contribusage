import Darwin
import Foundation

/// Reads line files incrementally (SPEC §8.3.5, FR-26): per file its identity, offset and pending partial line, so each
/// read returns only the complete lines appended since the last one. Decoding the lines is the provider's job.
public struct IncrementalJSONLReader: Sendable {
    public struct Lines: Sendable {
        /// The file was read from 0 because its identity changed or it shrank: drop what it contributed before.
        public let isRescan: Bool
        /// Complete lines without their newline; empty lines are left out.
        public let lines: [Data]
    }

    private struct State {
        /// Device and inode.
        var identity: (dev_t, ino_t)
        /// Bytes read so far, `pending` included.
        var offset: UInt64 = 0
        var pending = Data()
    }

    private var files: [URL: State] = [:]

    public init() {}

    /// `nil` when the file no longer exists; its state is dropped (frozen history is not the reader's concern).
    public mutating func read(_ url: URL) throws -> Lines? {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch CocoaError.fileNoSuchFile {
            files[url] = nil
            return nil
        }
        defer { try? handle.close() }

        // Identity and size from the open descriptor, so a replace between stat and read cannot mix two files.
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let identity = (info.st_dev, info.st_ino)
        let previous = files[url]
        let isRescan = previous.map { $0.identity != identity || UInt64(info.st_size) < $0.offset } ?? false
        var state = (isRescan ? nil : previous) ?? State(identity: identity)

        // ponytail: reads the whole appended range at once; stream in chunks if single files reach hundreds of MB.
        try handle.seek(toOffset: state.offset)
        let chunk = try handle.readToEnd() ?? Data()
        state.offset += UInt64(chunk.count)
        // The last piece is the incomplete line, empty when the data ends with a newline.
        var pieces = (state.pending + chunk).split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        state.pending = Data(pieces.removeLast())
        files[url] = state
        return Lines(isRescan: isRescan, lines: pieces.filter { !$0.isEmpty }.map { Data($0) })
    }
}
