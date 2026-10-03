import Foundation
import Testing

@testable import ContribusageClaudeCode

private let de = Locale(identifier: "de")

/// NFR-10, ADR-033: the texts `/usage` prints that the app translates; anything else stays as printed.
@Test func windowLabelsInGerman() {
    #expect(ClaudeCodeProvider.toolText("Current session", locale: de) == "Aktuelle Sitzung")
    #expect(ClaudeCodeProvider.toolText("Current week (all models)", locale: de) == "Aktuelle Woche (alle Modelle)")
    #expect(ClaudeCodeProvider.toolText("Current week (Opus)", locale: de) == "Aktuelle Woche (Opus)")
    #expect(ClaudeCodeProvider.toolText("Extra usage", locale: de) == "Extra usage")
    #expect(ClaudeCodeProvider.toolText("Current session", locale: Locale(identifier: "en")) == "Current session")
}

@Test func insightsPeriodsAndSummariesInGerman() {
    #expect(ClaudeCodeProvider.toolText("Last 24h", locale: de) == "Letzte 24 Std.")
    #expect(ClaudeCodeProvider.toolText("Last 7d", locale: de) == "Letzte 7 Tage")
    #expect(ClaudeCodeProvider.toolText("668 requests · 8 sessions", locale: de) == "668 Anfragen · 8 Sitzungen")
    #expect(ClaudeCodeProvider.toolText("1 request · 1 session", locale: de) == "1 Anfrage · 1 Sitzung")
    #expect(ClaudeCodeProvider.toolText("5 requests · 2 agents", locale: de) == "5 Anfragen · 2 agents")
    #expect(
        ClaudeCodeProvider.toolText("80% of your usage was at >150k context", locale: de)
            == "80% of your usage was at >150k context")
    #expect(
        ClaudeCodeProvider.toolText("1 request · 1 session", locale: Locale(identifier: "en"))
            == "1 request · 1 session")
}

/// The insights note, sentence by sentence; both separators the tool has printed are known.
@Test func insightsNoteInGerman() {
    let german =
        "Ungefähr, basierend auf lokalen Sitzungen auf diesem Mac; andere Geräte und claude.ai sind nicht enthalten. "
        + "Verhaltensweisen sind unabhängige Merkmale, keine Aufschlüsselung."
    for separator in [";", " —"] {
        let note =
            "Approximate, based on local sessions on this machine\(separator) does not include other devices or "
            + "claude.ai. Behaviors are independent characteristics, not a breakdown."
        #expect(ClaudeCodeProvider.toolText(note, locale: de) == german)
    }
    #expect(
        ClaudeCodeProvider.toolText("Approximate. Unknown sentence.", locale: de) == "Approximate. Unknown sentence.")
}
