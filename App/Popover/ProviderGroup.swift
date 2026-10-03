import Charts
import ContribusageCore
import SwiftUI

/// One provider: header, then limits, activity and insights (FR-4, FR-31).
struct ProviderGroup: View {
    let group: AppState.ProviderGroupState
    @Environment(AppState.self) private var appState
    @AppStorage("showInsights") private var showInsights = true

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
                    content: { LimitsSection(report: $0, descriptor: descriptor) })
            }
            if let activity = group.activity {
                SectionStateView(
                    state: activity, displayName: descriptor.displayName, placeholder: .placeholder(descriptor.id),
                    content: { ActivitySection(report: $0, descriptor: descriptor) })
            }
            if showInsights, let insights = group.insights {
                InsightsSection(insights: insights, descriptor: descriptor)
            }
        }
    }
}

struct LimitsSection: View {
    let report: LimitsReport
    let descriptor: ProviderDescriptor
    @Environment(\.now) private var now

    var body: some View {
        ForEach(report.windows, id: \.label) { window in
            let reset = window.isReset(at: now)
            let percent = reset ? 0 : window.usedPercent  // FR-11: unknown, drawn empty
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(descriptor.toolText(window.label))
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
        let used: String? =
            if reset { nil } else if window.isBelowOne {
                String(localized: "less than 1 percent used")
            } else {
                String(localized: "\(Int(window.usedPercent)) percent used")
            }
        return [
            descriptor.displayName, descriptor.toolText(window.label), used, window.resetText(at: now, width: .wide),
        ].compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// FR-38: one period at a time, its shares, then the top three of each ranking; the tool's note as the title's tooltip.
struct InsightsSection: View {
    let insights: Insights
    /// Its `toolText` translates the periods, summaries and note (ADR-033).
    let descriptor: ProviderDescriptor
    /// A period's label, so the choice survives a refresh.
    @State private var selected: String?

    var body: some View {
        DisclosureGroup {
            let period = insights.periods.first { $0.label == selected } ?? insights.periods[0]
            VStack(alignment: .leading, spacing: 6) {
                if insights.periods.count > 1 {
                    Picker("Period", selection: Binding(get: { period.label }, set: { selected = $0 })) {
                        ForEach(insights.periods, id: \.label) { Text(descriptor.toolText($0.label)).tag($0.label) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                }
                Text(descriptor.toolText(period.summary)).font(.caption).foregroundStyle(.secondary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    ForEach(period.shares, id: \.label, content: row)
                    ForEach(period.rankings, id: \.title) { ranking in
                        Text(ranking.title).font(.caption).foregroundStyle(.secondary).padding(.top, 5)
                        ForEach(ranking.shown, id: \.label, content: row)
                    }
                }
                .font(.callout)
            }
            .padding(.top, 6)
        } label: {
            let note = insights.note.map(descriptor.toolText) ?? ""
            Text("Insights").help(note).accessibilityHint(note)
        }
    }

    private func row(_ share: Insights.Share) -> some View {
        GridRow {
            Text(share.label).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Text(share.percent?.formatted(.percent) ?? "").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Insights.Ranking {
    /// The top three items, as the popover and Copy show them (FR-38, FR-42).
    var shown: ArraySlice<Insights.Share> { items.prefix(3) }
}

/// US-5: today's numbers, then total tokens of the last 7 days; categories the provider does not report are hidden
/// (SPEC §10.4).
struct ActivitySection: View {
    let report: ActivityReport
    let descriptor: ProviderDescriptor
    @Environment(\.now) private var now

    var body: some View {
        let figures = Figures(report: report, now: now)
        VStack(alignment: .leading, spacing: 4) {
            Text("On this Mac").font(.subheadline).foregroundStyle(.secondary)
            Text(figures.todayText)
            Text(figures.categoriesText(descriptor.tokenCategories)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)  // wraps; the menu bar window proposes too little height
            HStack(alignment: .bottom) {
                Chart(figures.week, id: \.day) {
                    // Today in full, the days before muted.
                    BarMark(x: .value("Day", $0.day, unit: .day), y: .value("Tokens", $0.tokens), width: .ratio(0.6))
                        .foregroundStyle(Color.accentColor.opacity($0.day == figures.week.last?.day ? 1 : 0.45))
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(descriptor.displayName) tokens per day, last 7 days")
                .accessibilityValue(figures.weekSummary)
                Text("last 7 days").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// What the section shows, shared with Copy Statistics (FR-42).
    struct Figures {
        let today: ActivityDay
        /// Oldest first, today last; days without activity count as 0.
        let week: [(day: Date, tokens: Int)]

        init(report: ActivityReport, now: Date, calendar: Calendar = .current) {
            let byDay = Dictionary(report.days.map { ($0.day, $0) }, uniquingKeysWith: { $1 })
            week = (0..<7).reversed().map {
                let day = calendar.date(byAdding: .day, value: -$0, to: now)!
                return (day, byDay[DayKey(day, calendar: calendar)]?.tokens.total ?? 0)
            }
            let todayKey = DayKey(now, calendar: calendar)
            today =
                byDay[todayKey]
                ?? ActivityDay(day: todayKey, requests: 0, sessions: 0, tokens: TokenCounts(), byModel: [:])
        }

        var todayText: String {
            String(
                localized:
                    "Today: \(today.requests) requests · \(today.sessions) sessions · \(Self.compact(today.tokens.total))"
            )
        }

        /// SPEC §11.7: "highest Thursday with 5.1M", then every day.
        var weekSummary: String {
            func weekday(_ day: Date) -> String { day.formatted(.dateTime.weekday(.wide)) }
            guard let highest = week.max(by: { $0.tokens < $1.tokens }), highest.tokens > 0 else {
                return String(localized: "no tokens")
            }
            let days = week.map { "\(weekday($0.day)) \(Self.compact($0.tokens))" }.joined(separator: ", ")
            return String(localized: "highest \(weekday(highest.day)) with \(Self.compact(highest.tokens)). \(days)")
        }

        func categoriesText(_ categories: Set<TokenCategory>) -> String {
            let shown: [(category: TokenCategory, label: String, count: KeyPath<TokenCounts, Int>)] = [
                (.input, String(localized: "Input"), \.input), (.output, String(localized: "Output"), \.output),
                (.cacheRead, String(localized: "Cache read"), \.cacheRead),
                (.cacheWrite, String(localized: "Cache write"), \.cacheWrite),
            ]
            return shown.filter { categories.contains($0.category) }
                .map { "\($0.label) \(Self.compact(today.tokens[keyPath: $0.count]))" }.joined(separator: " · ")
        }

        /// SPEC §11.5: "4.2M", "812K".
        static func compact(_ tokens: Int) -> String { tokens.formatted(.number.notation(.compactName)) }
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
