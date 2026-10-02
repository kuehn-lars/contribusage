import Darwin
import Foundation

/// Reads line files incrementally (SPEC §8.3.5, FR-26): per file its identity, offset and pending partial line, so each
/// read hands over only the complete lines appended since the last one. Decoding the lines is the provider's job.
public struct IncrementalJSONLReader: Sendable {
    private struct State {
        /// Device and inode.
        var identity: (dev_t, ino_t)
        /// Bytes read so far, `pending` included.
        var offset: UInt64 = 0
        var pending = Data()
    }

    private var files: [URL: State] = [:]
    private let fileReader: any FileReading

    public init(fileReader: any FileReading) { self.fileReader = fileReader }

    /// Calls `body` with each complete line appended since the last read, in order, without its newline; empty lines
    /// are left out. The file is streamed through a fixed buffer and each line is released after `body` returns, so
    /// memory does not grow with the file (NFR-2).
    ///
    /// Returns `nil` when the file no longer exists; its state is dropped (frozen history is not the reader's concern).
    /// Otherwise whether the file was read from 0 because its identity changed or it shrank: then drop what it
    /// contributed before. When it throws, discard the lines `body` received: the next read hands them over again.
    public mutating func read(_ url: URL, lines body: (Data) -> Void) throws -> Bool? {
        let handle: FileHandle
        do {
            handle = try fileReader.handle(forReadingFrom: url)
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

        try handle.seek(toOffset: state.offset)
        try withUnsafeTemporaryAllocation(byteCount: 1 << 16, alignment: 1) { buffer in
            while true {
                let count = Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
                guard count >= 0 else {
                    if errno == EINTR { continue }
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                if count == 0 { break }
                state.offset += UInt64(count)
                let bytes = UnsafeRawBufferPointer(rebasing: buffer[..<count])
                var start = 0
                while let newline = memchr(buffer.baseAddress! + start, 0x0A, count - start) {
                    let end = buffer.baseAddress!.distance(to: newline)
                    state.pending.append(contentsOf: bytes[start..<end])
                    if !state.pending.isEmpty { body(state.pending) }
                    state.pending = Data()
                    start = end + 1
                }
                state.pending.append(contentsOf: bytes[start...])
            }
        }
        files[url] = state
        return isRescan
    }
}
