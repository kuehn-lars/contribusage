import ContribusageClaudeCode
import ContribusageCore
import Foundation

/// The only place that lists providers (FR-1); registration order is display order.
enum ProviderRegistration {
    static func all(time: any TimeSource) -> [any UsageProvider] {
        [
            ClaudeCodeProvider(
                runner: LiveProcessRunner(), paths: .live, home: .homeDirectory,
                shell: URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"),
                time: time,
                override: {
                    UserDefaults.standard.string(forKey: "provider.claude-code.pathOverride").map { URL(filePath: $0) }
                })
        ]
    }
}
