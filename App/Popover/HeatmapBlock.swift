import ContribusageCore
import ContribusageGitHub
import SwiftUI

/// The shared heatmap (FR-48, FR-49, ADR-032): a legend, then one grid of split cells (Combined) or one grid per layer
/// (Stacked); hovering a day shows its FR-49 line.
// ponytail: plain grids; T-5.11 owns keyboard and VoiceOver.
struct HeatmapBlock: View {
    @Environment(AppState.self) private var appState
    @Environment(\.now) private var now

    var body: some View {
        let (days, layers) = appState.heatmap(at: now)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Heatmap", systemImage: "calendar").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                HeatmapLegend(layers: layers)
            }
            HeatmapGrids(days: days, layers: layers, style: appState.layout.heatmapStyle) {
                HeatmapLayer.line($0, layers: layers.map(\.layer))
            }
        }
    }
}

/// A layer as drawn: in its hue, dimmed while its source is stale or failed (SPEC §11.4).
struct ShownLayer {
    let layer: HeatmapLayer
    let color: Color
    var dimmed = false
}

/// Each layer's name in its hue (FR-49).
struct HeatmapLegend: View {
    let layers: [ShownLayer]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(layers, id: \.layer.id) { shown in
                Label {
                    Text(shown.layer.name)
                } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(shown.color).frame(width: 8, height: 8)
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// FR-49: Combined is one grid with a stripe per layer active that day in each cell; Stacked one grid per layer,
/// sharing the week columns. `line` is the tooltip of a day; `nil` shows none.
struct HeatmapGrids: View {
    let days: [DayKey]
    let layers: [ShownLayer]
    let style: HeatmapStyle
    var line: ((DayKey) -> String)?

    var body: some View {
        switch style {
        case .combined:
            grid(layers)
        case .stacked:
            VStack(spacing: 6) { ForEach(layers, id: \.layer.id) { grid([$0]) } }
        }
    }

    private func grid(_ layers: [ShownLayer]) -> some View {
        WeekColumns {
            ForEach(days, id: \.self) { day in
                // Stripes only for the layers active that day: one active layer fills the cell (FR-49).
                let active = layers.filter { ($0.layer.levels[day] ?? 0) > 0 }
                HStack(spacing: 0) {
                    if active.isEmpty { Rectangle().fill(.quaternary) }  // SPEC §11.4: level 0 the neutral fill
                    ForEach(active, id: \.layer.id) { shown in
                        // SPEC §11.4: four steps of the hue from 40 % to full.
                        Rectangle()
                            .fill(shown.color.opacity(0.2 + 0.2 * Double(shown.layer.levels[day] ?? 0)))
                            .opacity(shown.dimmed ? 0.5 : 1)
                    }
                }
                .clipShape(.rect(cornerRadius: 2))
                .help(line?(day) ?? "")
            }
        }
    }
}

/// Days in columns of 7, top-aligned, as square cells sharing the proposed width; every column but the last is full, as
/// in GitHub's weeks after the first. The height follows from the width and never from the proposal: the menu bar window
/// proposes too little height, and `aspectRatio` cells shrank to dots.
private struct WeekColumns: Layout {
    private let gap: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let columns = (subviews.count + 6) / 7
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(columns) * (10 + gap) - gap
        let rows = min(subviews.count, 7)
        return CGSize(width: width, height: CGFloat(rows) * (side(width, columns) + gap) - gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = side(bounds.width, (subviews.count + 6) / 7)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(index / 7) * (side + gap),
                    y: bounds.minY + CGFloat(index % 7) * (side + gap)),
                proposal: ProposedViewSize(width: side, height: side))
        }
    }

    private func side(_ width: CGFloat, _ columns: Int) -> CGFloat {
        max((width - gap * CGFloat(columns - 1)) / CGFloat(columns), 0)
    }
}

extension AppState {
    /// FR-48, SPEC §11.4: the shown days and each layer from its source's last snapshot, stale or failed ones included
    /// and dimmed like their section. A provider's days from its first reported day on count 0 when unreported; earlier
    /// days are "no data".
    func heatmap(at now: Date) -> (days: [DayKey], layers: [ShownLayer]) {
        let days = HeatmapLayer.days(through: now, calendar: .current)
        return (days, heatmapSources.compactMap { layer($0, days: days, at: now) })
    }

    /// A source's layer over `days`; `nil` for the heatmap block itself.
    func layer(_ source: BlockID, days: [DayKey], at now: Date) -> ShownLayer? {
        switch source {
        case .github:
            let shown = Set(days)
            let contributions = github.snapshot?.value.calendar.weeks.joined().filter { shown.contains($0.date) } ?? []
            let layer = HeatmapLayer(
                id: .github, name: "GitHub",
                values: Dictionary(uniqueKeysWithValues: contributions.map { ($0.date, $0.count) }),
                levels: Dictionary(uniqueKeysWithValues: contributions.map { ($0.date, $0.level.rawValue) }))
            let stale = github.snapshot?.isStale(at: now, after: GitHubReport.policy.staleAfter) ?? false
            return ShownLayer(layer: layer, color: .green, dimmed: stale || github.isFailed)
        case .provider(let id):
            let group = group(id)
            let reported = group.activity?.snapshot?.value.days ?? []  // oldest first
            let tokens = Dictionary(reported.map { ($0.day, $0.tokens.total) }, uniquingKeysWith: +)
            let shown = reported.first.map { first in days.filter { $0 >= first.day } } ?? []
            let layer = HeatmapLayer.quartiled(
                source, name: group.descriptor.displayName,
                values: Dictionary(uniqueKeysWithValues: shown.map { ($0, tokens[$0, default: 0]) }))
            return ShownLayer(
                layer: layer, color: group.descriptor.heatmapHue.color, dimmed: group.activity?.isFailed ?? false)
        case .heatmap:
            return nil
        }
    }
}

extension SourceState {
    fileprivate var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

extension HeatmapHue {
    /// SPEC §11.4: system colors, which adapt to light and dark.
    var color: Color {
        switch self {
        case .orange: .orange
        case .blue: .blue
        case .purple: .purple
        case .teal: .teal
        case .pink: .pink
        case .indigo: .indigo
        }
    }
}
