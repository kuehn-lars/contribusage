import Foundation
import Testing

/// NFR-17: the core imports no other package target, and every other target imports only the core.
/// Checks the sources rather than `Package.swift`, so an added dependency cannot quietly widen the rule.
@Test func targetsImportOnlyTheCore() throws {
    let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources")
    let files = try FileManager.default.subpathsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
    // Also matches attributed and access-level imports: `@_spi(X) import`, `public import`, `import struct`.
    let importLine = /^\s*(?:@\w+(?:\([^)]*\))?\s+|\w+\s+)*import\s+(?:\w+\s+)?(Contribusage\w*)/
        .anchorsMatchLineEndings()

    var violations: [String] = []
    for file in files {
        let target = file.prefix { $0 != "/" }
        let allowed = target == "ContribusageCore" ? [] : ["ContribusageCore"]
        for match in try String(contentsOf: sources.appending(path: file), encoding: .utf8).matches(of: importLine)
        where !allowed.contains(String(match.1)) {
            violations.append("\(file) imports \(match.1)")
        }
    }
    #expect(!files.isEmpty, "no sources found under \(sources.path)")
    #expect(violations == [])
}
