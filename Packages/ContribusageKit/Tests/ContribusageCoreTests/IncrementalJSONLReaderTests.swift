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

private func strings(_ lines: [Data]) -> [String] { lines.map { String(decoding: $0, as: UTF8.self) } }

/// FR-26: only appended complete lines; an incomplete last line waits for its newline.
@Test func readsOnlyAppendedCompleteLines() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n\nb\n{\"c\":".utf8).write(to: url)
    var reader = IncrementalJSONLReader()

    let first = try reader.read(url)
    #expect(first.map { strings($0.lines) } == ["a", "b"] && first?.isRescan == false)

    let unchanged = try reader.read(url)
    #expect(unchanged?.lines == [])
    try append("1}\nd", to: url)
    let completed = try reader.read(url)
    #expect(completed.map { strings($0.lines) } == ["{\"c\":1}"])
    try append("\n", to: url)
    let last = try reader.read(url)
    #expect(last.map { strings($0.lines) } == ["d"])
}

/// SPEC 8.3.5: a shrunk file is read again from 0.
@Test func rescansAShrunkFile() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\nb\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader()
    _ = try reader.read(url)

    try Data("c\n".utf8).write(to: url)
    let lines = try reader.read(url)
    #expect(lines.map { strings($0.lines) } == ["c"] && lines?.isRescan == true)
}

/// SPEC 8.3.5: a replaced file (new inode, for example an atomic rewrite) is read again from 0, even when it grew.
@Test func rescansAReplacedFile() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader()
    _ = try reader.read(url)

    try Data("x\ny\n".utf8).write(to: url, options: .atomic)
    let lines = try reader.read(url)
    #expect(lines.map { strings($0.lines) } == ["x", "y"] && lines?.isRescan == true)
}

/// SPEC 8.3.5: a deleted file reads as nil and its state is dropped, so a new file at the path starts fresh.
@Test func deletedFileReadsNil() throws {
    let url = temporaryFile()
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("a\n".utf8).write(to: url)
    var reader = IncrementalJSONLReader()
    _ = try reader.read(url)

    try FileManager.default.removeItem(at: url)
    let gone = try reader.read(url)
    #expect(gone == nil)
    try Data("b\n".utf8).write(to: url)
    let lines = try reader.read(url)
    #expect(lines.map { strings($0.lines) } == ["b"] && lines?.isRescan == false)
}
