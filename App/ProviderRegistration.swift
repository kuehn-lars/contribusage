import ContribusageClaudeCode
import ContribusageCore
import Foundation

/// The only place that lists providers (FR-1); registration order is display order.
enum ProviderRegistration {
    static func all(time: any TimeSource) -> [any UsageProvider] {
        let providers: [any UsageProvider] = [
            ClaudeCodeProvider(
                runner: LiveProcessRunner(), fileEvents: FSEventsFileEvents(), fileReader: LiveFileReader(),
                paths: .live, home: .homeDirectory,
                shell: URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"),
                time: time,
                override: {
                    UserDefaults.standard.string(forKey: "provider.claude-code.pathOverride").map { URL(filePath: $0) }
                })
        ]
        #if CONTRIBUSAGE_FAKE_PROVIDER
            return providers + [DebugFakeProvider()]  // debug only, US-11
        #else
            return providers
        #endif
    }
}
