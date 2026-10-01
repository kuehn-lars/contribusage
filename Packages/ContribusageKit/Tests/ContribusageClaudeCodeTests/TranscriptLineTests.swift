import ContribusageClaudeCode
import Foundation
import Testing

private func decode(_ json: String) throws -> TranscriptLine? {
    try TranscriptLine.decode(Data(json.utf8))
}

/// SPEC Appendix E, plus unknown fields that must be ignored (FR-23).
@Test func decodesAssistantLine() throws {
    let line = try #require(
        try decode(
            """
            {"type":"assistant","isSidechain":true,"sessionId":"s1","timestamp":"2026-09-27T12:34:56.789Z",\
            "requestId":"req_1","extra":[1,2],"message":{"id":"msg_1","model":"claude-opus-5-5","content":[],\
            "usage":{"input_tokens":12,"cache_creation_input_tokens":1834,"cache_read_input_tokens":145210,\
            "output_tokens":421,"service_tier":"standard"}}}
            """))
    let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    let expected = try Date("2026-09-27T12:34:56.789Z", strategy: fractional)
    #expect(line.timestamp == expected)
    #expect(line.sessionID == "s1" && line.requestID == "req_1" && line.messageID == "msg_1")
    #expect(line.model == "claude-opus-5-5" && line.isSidechain)
    #expect((line.input, line.output, line.cacheWrite, line.cacheRead) == (12, 421, 1834, 145210))
}

@Test func missingOptionalFieldsDefault() throws {
    let line = try #require(
        try decode(
            #"{"type":"assistant","timestamp":"2026-09-27T12:00:00Z","message":{"model":"m","usage":{"output_tokens":3}}}"#
        ))
    #expect(line.sessionID == nil && line.requestID == nil && line.messageID == nil && !line.isSidechain)
    #expect((line.input, line.output, line.cacheWrite, line.cacheRead) == (0, 3, 0, 0))
}

@Test func skipsLinesWithoutUsage() throws {
    #expect(try decode(#"{"type":"user","timestamp":"2026-09-27T12:00:00Z","message":{"role":"user"}}"#) == nil)
    #expect(try decode(#"{"type":"assistant","timestamp":"2026-09-27T12:00:00Z","message":{"model":"m"}}"#) == nil)
    #expect(
        try decode(
            #"{"type":"assistant","timestamp":"2026-09-27T12:00:00Z","message":{"model":"<synthetic>","usage":{"output_tokens":0}}}"#
        ) == nil)
}

@Test func malformedLinesThrow() {
    #expect(throws: (any Error).self) { try decode("{not json") }
    #expect(throws: (any Error).self) { try decode(#"{"type":"assistant","message":{"model":"m","usage":{}}}"#) }
}
