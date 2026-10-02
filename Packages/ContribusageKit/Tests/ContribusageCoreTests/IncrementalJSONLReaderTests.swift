import ContribusageCore
import Foundation
import Testing

private func temporaryFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "contribusage-\(UUID()).jsonl")
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}

/// The lines one read hands over and whether it was a rescan; `nil` for a missing file.
private func read(_ reader: inout IncrementalJSONLReader, _ url: URL) throws -> (lines: [String], isRescan: Bool)? {
    var lines: [String] = []
    guard let isRescan = try reader.read(url, lines: { lines.append(String(decoding: $0, as: UTF8.self)) }) else {
        return nil
    }
    return (lines, isRescan)
}

/// FR-26: only appended complete lines; an incomplete last line waits for its newline.
@Test func readsOnlyAppendedCompleteLines() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n\nb\n{\"c\":".utf8).write(to: url)
    var reader = IncrementalJSONLReader(fileReader: LiveFileReader())

    let first = try read(&reader, url)
    #expect(first?.lines == ["a", "b"] && first?.isRescan == false)

    let unchanged = try read(&reader, url)
    #expect(unchanged?.lines == [])
    try append("1}\nd", to: url)
    let completed = try read(&reader, url)
    #expect(completed?.lines == ["{\"c\":1}"])
    try append("\n", to: url)
    let last = try read(&reader, url)
    #expect(last?.lines == ["d"])
}

/// SPEC 8.3.5: a shrunk file is read again from 0.
@Test func rescansAShrunkFile() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\nb\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader(fileReader: LiveFileReader())
    _ = try read(&reader, url)

    try Data("c\n".utf8).write(to: url)
    let lines = try read(&reader, url)
    #expect(lines?.lines == ["c"] && lines?.isRescan == true)
}

/// SPEC 8.3.5: a replaced file (new inode, for example an atomic rewrite) is read again from 0, even when it grew.
@Test func rescansAReplacedFile() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader(fileReader: LiveFileReader())
    _ = try read(&reader, url)

    try Data("x\ny\n".utf8).write(to: url, options: .atomic)
    let lines = try read(&reader, url)
    #expect(lines?.lines == ["x", "y"] && lines?.isRescan == true)
}

/// SPEC 8.3.5: a deleted file reads as nil and its state is dropped, so a new file at the path starts fresh.
@Test func deletedFileReadsNil() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader(fileReader: LiveFileReader())
    _ = try read(&reader, url)

    try FileManager.default.removeItem(at: url)
    let gone = try read(&reader, url)
    #expect(gone == nil)
    try Data("b\n".utf8).write(to: url)
    let lines = try read(&reader, url)
    #expect(lines?.lines == ["b"] && lines?.isRescan == false)
}

/// Lines are whole however they fall across the reader's buffer, also a line longer than it that waits for its newline.
@Test func readsLinesAcrossBufferBoundaries() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    let lines = [1, 70_000, 3, 140_000, 65_535, 65_536, 65_537, 2].enumerated().map { index, count in
        String(repeating: Character(UnicodeScalar(UInt8(97 + index))), count: count)
    }
    try Data((lines.joined(separator: "\n") + "\n" + String(repeating: "z", count: 100_000)).utf8).write(to: url)
    var reader = IncrementalJSONLReader(fileReader: LiveFileReader())

    #expect(try read(&reader, url)?.lines == lines)
    try append("z\n", to: url)
    #expect(try read(&reader, url)?.lines == [String(repeating: "z", count: 100_001)])
}

/// NFR-2: a read frees its file data on return, even when the caller reads many files in one go without draining an
/// autorelease pool (the activity source's whole scan is a single actor job).
@Test func readsWithoutAccumulatingFileData() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(String(repeating: String(repeating: "x", count: 999) + "\n", count: 8_000).utf8).write(to: url)
    let before = mallocInUse()

    for _ in 0..<16 {
        var reader = IncrementalJSONLReader(fileReader: LiveFileReader())
        _ = try read(&reader, url)
    }
    // Reading through an autoreleased `Data` per file kept all 16 reads of 8 MB alive: 128 MB.
    #expect(mallocInUse() - before < 48_000_000)
}

private func mallocInUse() -> Int {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return stats.size_in_use
}
