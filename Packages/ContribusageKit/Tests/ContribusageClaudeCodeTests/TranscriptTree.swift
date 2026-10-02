import ContribusageCore
import Foundation

/// A synthetic Claude Code transcript tree for the NFR-7 test: `<project>/<session>.jsonl`, some sessions with subagent
/// files under `<project>/<session>/subagents/` (SPEC §8.3.1). Lines are shaped like real ones (SPEC Appendix E plus
/// message content of up to tens of KB), each response is written as one line per content block repeating its usage
/// (SPEC §8.3.3), between user lines carrying tool results. Timestamps spread over the 30 days before `end`. The same
/// seed writes the same bytes.
enum TranscriptTree {
    /// What was written; `requests` and `tokens` are what the activity source must count.
    struct Summary {
        var files = 0
        var lines = 0
        var usageLines = 0
        var requests = 0
        var bytes = 0
        var tokens = TokenCounts()
    }

    static func generate(in projects: URL, bytes target: Int, end: Date, seed: UInt64 = 1) throws -> Summary {
        var writer = Writer(rng: SplitMix64(state: seed), end: end)
        while writer.summary.bytes < target {
            let budget = Int(Double(target) / 40 * pow(Double.random(in: 0...1, using: &writer.rng), 3))
            let project = projects.appending(
                path: "-Users-octocat-code-project-\(Int.random(in: 0..<12, using: &writer.rng))")
            let session = writer.uuid()
            let start = end.addingTimeInterval(-30 * 86_400 + .random(in: 0..<(28 * 86_400), using: &writer.rng))
            try writer.file(project.appending(path: "\(session).jsonl"), session, start, budget, sidechain: false)
            guard Int.random(in: 0..<10, using: &writer.rng) < 4 else { continue }
            for _ in 0..<Int.random(in: 1...3, using: &writer.rng) {
                let agent = project.appending(path: "\(session)/subagents/agent-\(writer.hex()).jsonl")
                try writer.file(agent, session, start, budget / 4, sidechain: true)
            }
        }
        return writer.summary
    }

    private struct Writer {
        var rng: SplitMix64
        let end: Date
        var summary = Summary()
        /// Message content is cut from this; plain words, so it needs no JSON escaping.
        private let filler: [UInt8]
        /// Written out every 64 KB, so generating leaves no large freed blocks behind to blur the footprint baseline.
        private var out: [UInt8] = []
        private static let stamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

        init(rng: SplitMix64, end: Date) {
            self.rng = rng
            self.end = end
            let words = ["the", "func", "return", "let", "file", "test", "swift", "build", "error", "value", "view"]
            var text = ""
            while text.utf8.count < 65_536 { text += words.randomElement(using: &self.rng)! + " " }
            filler = Array(text.utf8)
        }

        mutating func hex() -> String { String(rng.next(), radix: 16) }

        mutating func uuid() -> String {
            let digits = Array(String(format: "%016llx%016llx", rng.next(), rng.next()))
            return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(digits[$0]) }.joined(separator: "-")
        }

        /// Writes alternating user and assistant turns until the file holds `budget` bytes, at least one response.
        mutating func file(_ url: URL, _ session: String, _ start: Date, _ budget: Int, sidechain: Bool) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            var written = 0
            var time = start
            let header =
                #""isSidechain":\#(sidechain),"userType":"external","cwd":"/Users/octocat/code/project","#
                + #""sessionId":"\#(session)","version":"2.1.0","gitBranch":"main""#
            repeat {
                time += .random(in: 1...30, using: &rng)
                let result = Bool.random(using: &rng) ? Int.random(in: 4_000...30_000, using: &rng) : 0
                line(
                    time,
                    #"{"parentUuid":"\#(uuid())",\#(header),"type":"user","message":{"role":"user","content":"#
                        + #"[{"tool_use_id":"toolu_\#(hex())","type":"tool_result","content":""#,
                    text: Int.random(in: 200...4_000, using: &rng)
                        + (Int.random(in: 0..<7, using: &rng) == 0 ? result : 0),
                    #""}]},"uuid":"\#(uuid())","timestamp":"#)

                let models = ["claude-opus-5-5", "claude-opus-5-5", "claude-sonnet-5", "claude-haiku-4-5"]
                let model = sidechain ? "claude-haiku-4-5" : models.randomElement(using: &rng)!
                let usage = TokenCounts(
                    input: .random(in: 1...50, using: &rng), output: .random(in: 10...2_000, using: &rng),
                    cacheWrite: .random(in: 0...5_000, using: &rng),
                    cacheRead: .random(in: 10_000...200_000, using: &rng))
                let message = "msg_\(hex())"
                let request = "req_\(hex())"
                let blocks = Int.random(in: 1...4, using: &rng)
                for block in 0..<blocks {
                    time += .random(in: 0.1...3, using: &rng)
                    let kind =
                        block == blocks - 1 ? "text" : ["thinking", "text", "tool_use"].randomElement(using: &rng)!
                    line(
                        time,
                        #"{"parentUuid":"\#(uuid())",\#(header),"message":{"id":"\#(message)","type":"message","#
                            + #""role":"assistant","model":"\#(model)","content":[{"type":"\#(kind)","text":""#,
                        text: .random(in: 50...3_000, using: &rng),
                        #""}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":\#(usage.input),"#
                            + #""cache_creation_input_tokens":\#(usage.cacheWrite),"#
                            + #""cache_read_input_tokens":\#(usage.cacheRead),"output_tokens":\#(usage.output),"#
                            + #""service_tier":"standard"}},"requestId":"\#(request)","type":"assistant","#
                            + #""uuid":"\#(uuid())","timestamp":"#)
                }
                summary.usageLines += blocks
                summary.requests += 1
                summary.tokens += usage
                if out.count >= 1 << 16 || written + out.count >= budget {
                    try handle.write(contentsOf: out)
                    written += out.count
                    out.removeAll(keepingCapacity: true)
                }
            } while written < budget
            summary.files += 1
            summary.bytes += written
        }

        /// `prefix`, `text` bytes of filler, `suffix`, the timestamp, the line end.
        private mutating func line(_ time: Date, _ prefix: String, text: Int, _ suffix: String) {
            let from = Int.random(in: 0..<(filler.count - text), using: &rng)
            out += prefix.utf8
            out += filler[from..<(from + text)]
            out += suffix.utf8
            out += #""\#(time.formatted(Self.stamp))"}"#.utf8
            out.append(UInt8(ascii: "\n"))
            summary.lines += 1
        }
    }
}

/// Seeded, so the tree is the same on every run.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
