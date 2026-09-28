import ContribusageClaudeCode
import ContribusageCore
import Testing

/// Existing data lives under `providers/claude-code/`; a new raw value would orphan it (SPEC §7.5, §10.7).
@Test func claudeCodeIDNeverChanges() {
    #expect(ProviderID.claudeCode.rawValue == "claude-code")
}
