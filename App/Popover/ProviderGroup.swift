import Charts
import ContribusageCore
import SwiftUI

/// One provider: header, then limits, activity and insights (FR-4, FR-31).
struct ProviderGroup: View {
    let group: AppState.ProviderGroupState
    @Environment(AppState.self) private var appState

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
                    retry: appState.refresh,
                    content: { LimitsSection(report: $0, providerName: descriptor.displayName) })
            }
            if let activity = group.activity {
                SectionStateView(
                    state: activity, displayName: descriptor.displayName, placeholder: .placeholder(descriptor.id),
                    content: ActivitySection.init)
            }
            if descriptor.capabilities.contains(.insights), let insights = group.limits?.snapshot?.value.insights {
                InsightsSection(insights: insights)
            }
        }
    }
}

struct LimitsSection: View {
    let report: LimitsReport
    let providerName: String
    @Environment(\.now) private var now

    var body: some View {
        ForEach(report.windows, id: \.label) { window in
            let reset = window.isReset(at: now)
            let percent = reset ? 0 : window.usedPercent  // FR-11: unknown, drawn empty
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(window.label)
                    Spacer()
                    Text(window.percentText(at: now)).monospacedDigit()
                }
                Capsule().fill(.quaternary).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(color(percent)).frame(width: proxy.size.width * min(percent, 100) / 100)
                        }
                    }
                if let resetsAt = window.resetsAt, let resetText = window.resetText(at: now) {
                    Text(resetText).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help(resetsAt.formatted(.dateTime.weekday().day().month().hour().minute()))  // US-2
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(window, reset: reset))
        }
    }

    /// SPEC §11.4.
    private func color(_ percent: Double) -> Color {
        percent >= 90 ? .red : percent >= 70 ? .orange : .accentColor
    }

    /// SPEC §11.7: "Claude Code, Current session, 23 percent used, resets in 2 hours 10 minutes".
    private func accessibilityLabel(_ window: UsageWindow, reset: Bool) -> String {
        let used =
            reset ? nil : window.isBelowOne ? "less than 1 percent used" : "\(Int(window.usedPercent)) percent used"
        return [providerName, window.label, used, window.resetText(at: now, width: .wide)].compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// FR-38: one period at a time, its shares, then the top three of each ranking; the tool's note as the title's tooltip.
struct InsightsSection: View {
    let insights: Insights
    /// A period's label, so the choice survives a refresh.
    @State private var selected: String?

    var body: some View {
        DisclosureGroup {
            let period = insights.periods.first { $0.label == selected } ?? insights.periods[0]
            VStack(alignment: .leading, spacing: 6) {
                if insights.periods.count > 1 {
                    Picker("Period", selection: Binding(get: { period.label }, set: { selected = $0 })) {
                        ForEach(insights.periods, id: \.label) { Text($0.label).tag($0.label) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Text(period.summary).font(.caption).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    ForEach(period.shares, id: \.label, content: row)
                    ForEach(period.rankings, id: \.title) { ranking in
                        Text(ranking.title).font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                        ForEach(ranking.items.prefix(3), id: \.label, content: row)
                    }
                }
                .font(.callout)
            }
            .padding(.top, 6)
        } label: {
            Text("Insights").help(insights.note ?? "").accessibilityHint(insights.note ?? "")
        }
    }

    private func row(_ share: Insights.Share) -> some View {
        GridRow {
            Text(share.label).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(share.percent.map { "\($0)%" } ?? "").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
