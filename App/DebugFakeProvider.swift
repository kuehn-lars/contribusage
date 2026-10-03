#if CONTRIBUSAGE_FAKE_PROVIDER
    import ContribusageCore
    import Foundation

    /// US-11: a second provider for checking the app by hand, shaped like the test support `FakeProvider` (one weekly
    /// window, pushed only, `input` and `output` tokens). Debug builds with the flag only (SPEC §15.5, §16.5).
    struct DebugFakeProvider: UsageProvider, LimitsSource, ActivitySource {
        let descriptor = ProviderDescriptor(
            id: ProviderID(rawValue: "fake"), displayName: "Fake Tool", symbolName: "hammer", heatmapHue: .blue,
            capabilities: [.limits, .activity], tokenCategories: [.input, .output], limitsPolicy: nil)
        var limits: (any LimitsSource)? { self }
        var activity: (any ActivitySource)? { self }

        func detectAvailability() async -> ProviderAvailability { .available(version: "1.0") }

        func fetch() async throws -> LimitsReport {
            throw SourceError.providerSpecific(code: "push-only", message: "limits are only pushed")
        }

        /// 85 % crosses the default thresholds, so a notification names this provider (SPEC §16.5).
        func pushedUpdates() -> AsyncStream<LimitsReport> {
            let window = UsageWindow(
                label: "This week", kind: .weekly, usedPercent: 85, isBelowOne: false,
                resetsAt: .now.addingTimeInterval(3 * 86400))
            let report = LimitsReport(
                provider: descriptor.id, windows: [window], billingNote: nil, insights: nil, rawOutput: nil)
            return AsyncStream { $0.yield(report) }
        }

        /// Every other day of the last 26 weeks, so its heatmap layer shows next to the others.
        func reports() -> AsyncStream<ActivityReport> {
            let days = stride(from: 181, through: 0, by: -2).map { ago in
                ActivityDay(
                    day: DayKey(.now.addingTimeInterval(-Double(ago) * 86400), calendar: .current),
                    requests: ago % 7 + 1, sessions: 1, tokens: TokenCounts(input: 100 * ago, output: 50 * ago),
                    byModel: [:])
            }
            let report = ActivityReport(provider: descriptor.id, days: days, skippedLines: 0)
            return AsyncStream { $0.yield(report) }
        }

        func rescan() async {}
    }
#endif
