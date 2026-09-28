import Charts
import ContribusageCore
import SwiftUI

/// One provider: header, then limits, activity and insights (FR-4, FR-31).
struct ProviderGroup: View {
    let group: AppState.ProviderGroupState

    var body: some View {
        let descriptor = group.descriptor
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: descriptor.displayName, symbolName: descriptor.symbolName,
                fetchedAt: group.limits?.snapshot?.fetchedAt)
            if let limits = group.limits {
                SectionStateView(
                    state: limits, displayName: descriptor.displayName,
                    staleAfter: descriptor.limitsPolicy?.staleAfter, placeholder: .placeholder(descriptor.id),
                    content: LimitsSection.init)
            }
            if let activity = group.activity {
                SectionStateView(
                    state: activity, displayName: descriptor.displayName, placeholder: .placeholder(descriptor.id),
                    content: ActivitySection.init)
            }
            if descriptor.capabilities.contains(.insights), let insights = group.limits?.snapshot?.value.insights {
                DisclosureGroup("Insights") {
                    Text(verbatim: insights).font(.caption).textSelection(.enabled)
                }
            }
        }
    }
}

struct LimitsSection: View {
    let report: LimitsReport
    @Environment(\.now) private var now

    var body: some View {
        ForEach(report.windows, id: \.label) { window in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(window.label)
                    Spacer()
                    Text(window.isBelowOne ? "<1%" : "\(Int(window.usedPercent))%").monospacedDigit()
                }
                Capsule().fill(.quaternary).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(color(window.usedPercent))
                                .frame(width: proxy.size.width * min(window.usedPercent, 100) / 100)
                        }
                    }
                if let resetsAt = window.resetsAt {
                    Text(resetText(resetsAt)).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    /// SPEC §11.4.
    private func color(_ percent: Double) -> Color {
        percent >= 90 ? .red : percent >= 70 ? .orange : .accentColor
    }

    // ponytail: rough SPEC §11.5 wording; T-2.7 owns the exact reset formatting and its tests.
    private func resetText(_ resetsAt: Date) -> String {
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 { return "reset" }
        if remaining > 24 * 3600 { return "resets \(resetsAt.formatted(.dateTime.weekday().hour().minute()))" }
        return
            "resets in \(Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))"
    }
}

struct ActivitySection: View {
    let report: ActivityReport

    var body: some View {
        let lastWeek = report.days.suffix(7)
        VStack(alignment: .leading, spacing: 4) {
            Text("On this Mac").font(.subheadline).foregroundStyle(.secondary)
            // ponytail: the newest day stands in for today; the activity task (T-4.x) matches the real date.
            if let today = lastWeek.last {
                Text(
                    "Today: \(today.requests) requests · \(today.sessions) sessions · \(today.tokens.total.formatted(.number.notation(.compactName)))"
                )
            }
            HStack(alignment: .bottom) {
                Chart(Array(lastWeek), id: \.day) { day in
                    BarMark(x: .value("Day", day.day.rawValue), y: .value("Tokens", day.tokens.total))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 32)
                Text("last 7 days").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension LimitsReport {
    static func placeholder(_ provider: ProviderID) -> LimitsReport {
        LimitsReport(
            provider: provider,
            windows: [
                UsageWindow(
                    label: "Current session", kind: .session, usedPercent: 20, isBelowOne: false, resetsAt: nil),
                UsageWindow(label: "Current week", kind: .weekly, usedPercent: 40, isBelowOne: false, resetsAt: nil),
            ],
            billingNote: nil, insights: nil, rawOutput: nil)
    }
}

extension ActivityReport {
    static func placeholder(_ provider: ProviderID) -> ActivityReport {
        let day = ActivityDay(
            day: DayKey(rawValue: "0"), requests: 100, sessions: 1, tokens: TokenCounts(), byModel: [:])
        return ActivityReport(provider: provider, days: [day], skippedLines: 0)
    }
}
