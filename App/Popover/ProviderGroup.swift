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
                    content: { ActivitySection(report: $0, categories: descriptor.tokenCategories) })
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

/// US-5: today's numbers, then total tokens of the last 7 days; categories the provider does not report are hidden
/// (SPEC §10.4).
struct ActivitySection: View {
    let report: ActivityReport
    let categories: Set<TokenCategory>
    @Environment(\.now) private var now

    var body: some View {
        let calendar = Calendar.current
        let byDay = Dictionary(report.days.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
        // Oldest first, today last; days without activity count as 0.
        let week = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: now)! }
        let tokens = week.map { byDay[DayKey($0, calendar: calendar)]?.tokens.total ?? 0 }
        let todayKey = DayKey(now, calendar: calendar)
        let today =
            byDay[todayKey] ?? ActivityDay(day: todayKey, requests: 0, sessions: 0, tokens: TokenCounts(), byModel: [:])
        VStack(alignment: .leading, spacing: 4) {
            Text("On this Mac").font(.subheadline).foregroundStyle(.secondary)
            Text(
                "Today: \(today.requests) requests · \(today.sessions) sessions · \(compact(today.tokens.total))"
            )
            let shown: [(category: TokenCategory, label: String, count: KeyPath<TokenCounts, Int>)] = [
                (.input, "Input", \.input), (.output, "Output", \.output), (.cacheRead, "Cache read", \.cacheRead),
                (.cacheWrite, "Cache write", \.cacheWrite),
            ]
            Text(
                shown.filter { categories.contains($0.category) }
                    .map { "\($0.label) \(compact(today.tokens[keyPath: $0.count]))" }.joined(separator: " · ")
            )
            .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom) {
                Chart(Array(zip(week, tokens)), id: \.0) { day, total in
                    BarMark(x: .value("Day", day, unit: .day), y: .value("Tokens", total))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tokens, last 7 days")
                .accessibilityValue(
                    zip(week, tokens).map { "\($0.formatted(.dateTime.weekday(.wide))): \(compact($1))" }
                        .joined(separator: ", "))
                Text("last 7 days").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// SPEC §11.5: "4.2M", "812K".
    private func compact(_ tokens: Int) -> String { tokens.formatted(.number.notation(.compactName)) }
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
