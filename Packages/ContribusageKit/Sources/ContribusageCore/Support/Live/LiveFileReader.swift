import Foundation

/// Reads the disk directly.
public struct LiveFileReader: FileReading {
    public init() {}

    public func enumerator(at folder: URL) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    }

    public func handle(forReadingFrom file: URL) throws -> FileHandle { try FileHandle(forReadingFrom: file) }

    public func contents(of file: URL) throws -> Data { try Data(contentsOf: file) }
}
