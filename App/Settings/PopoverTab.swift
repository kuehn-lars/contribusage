import ContribusageCore
import SwiftUI

/// SPEC §11.6 Popover tab (FR-44, FR-48, FR-49, US-13, ADR-034): every block in popover order, and every provider's
/// sections in theirs, reordered by drag. The open popover follows each change at once through `AppState.layout`.
// ponytail: the style picker's legend preview comes with the layer hues in T-5.16.
struct PopoverTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let ids = appState.providers.map(\.id)
        let blocks = appState.layout.arranged(registered: ids)
        Form {
            // One card per block, one form row per toggle: the form's own row height and separators space them.
            ForEach(blocks, id: \.self) { block in
                Section {
                    BlockRows(block: block, among: blocks) { appState.layout.move($0, to: block, registered: ids) }
                } header: {
                    if block == blocks.first { Text("Blocks") }
                } footer: {
                    if block == blocks.last { Text("Drag to change the order.").foregroundStyle(.secondary) }
                }
            }
            Section {
                Picker("Heatmap style", selection: $appState.layout.heatmapStyle) {
                    Text("Combined").tag(HeatmapStyle.combined)
                    Text("Stacked").tag(HeatmapStyle.stacked)
                }
            } footer: {
                Text("Stacked reads better from three layers on.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .labelStyle(RowLabel())
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One block: its visibility, "In heatmap" for a source with daily data, a provider's sections; greyed out with a note
/// while its source is off.
private struct BlockRows: View {
    let block: BlockID
    /// Every block, the ones this block's title row accepts.
    let among: [BlockID]
    /// Moves a block dropped on this block's title row into its place.
    let move: (BlockID) -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let isOn = appState.isOn(block)
        let (label, offNote, capabilities) = details
        Group {
            Toggle(isOn: $appState.layout.hiddenBlocks.excludes(block)) {
                label
                if !isOn { Text(offNote) }
            }
            .reorderable(block, among: among, scope: "block", preview: label, move: move)
            // A source with daily data has a heatmap layer (FR-48).
            if block == .github || capabilities.contains(.activity) {
                HStack {
                    Handle().hidden()
                    Toggle(isOn: $appState.layout.outOfHeatmap.excludes(block)) {
                        Label("In heatmap", systemImage: "square.grid.3x3.square")
                    }
                }
                .padding(.leading, 20)
            }
            if case .provider(let id) = block {
                // Scoped by the provider, so a section moves only within its group.
                let sections = appState.layout.sections(of: id).filter { capabilities.contains($0.capability) }
                ForEach(sections, id: \.self) { section in
                    Toggle(isOn: $appState.layout[shows: section, of: id]) { section.label }
                        .reorderable(section, among: sections, scope: id.rawValue, preview: section.label) {
                            appState.layout.move($0, to: section, of: id)
                        }
                        .padding(.leading, 20)
                }
            }
        }
        .foregroundStyle(isOn ? .primary : .secondary)
    }

    private var details: (label: Label<Text, Image>, offNote: LocalizedStringKey, capabilities: ProviderCapabilities) {
        switch block {
        case .provider(let id):
            let descriptor = appState.group(id).descriptor
            return (
                Label(descriptor.displayName, systemImage: descriptor.symbolName), "Off: turn it on in Providers.",
                descriptor.capabilities
            )
        case .heatmap: return (Label("Heatmap", systemImage: "calendar"), "No source that is on is in the heatmap.", [])
        case .github:
            return (Label("GitHub", systemImage: "square.grid.3x3.fill"), "Off: turn it on in the GitHub tab.", [])
        }
    }
}

extension SectionKind {
    fileprivate var label: Label<Text, Image> {
        switch self {
        case .limits: Label("Limits", systemImage: "gauge.with.dots.needle.33percent")
        case .activity: Label("Activity", systemImage: "chart.bar")
        case .insights: Label("Insights", systemImage: "lightbulb")
        }
    }
}

extension View {
    /// A row for `item` that is dragged by its handle or label and dropped on another row of `items` in the same
    /// `scope`, whose place it then takes through `move`. `onMove` reorders only inside a `List`, and a grouped `Form`
    /// ignores it.
    fileprivate func reorderable<Item: RawRepresentable<String>>(
        _ item: Item, among items: [Item], scope: String, preview: some View, move: @escaping (Item) -> Void
    ) -> some View {
        // The drag carries "<scope>/<raw value>", so a drop from another scope matches nothing here.
        let key = { (item: Item) in "\(scope)/\(item.rawValue)" }
        return modifier(
            Reorderable(payload: key(item), preview: preview) { dropped in
                guard let moved = items.first(where: { key($0) == dropped }) else { return false }
                move(moved)
                return true
            })
    }
}

/// While a row is over another, the target lights up; on the drop the rows slide to their new places, unless Reduce
/// Motion is on. The drag shows the row's label on a material card instead of a snapshot of its controls.
private struct Reorderable<Preview: View>: ViewModifier {
    let payload: String
    let preview: Preview
    let drop: (String) -> Bool
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        HStack {
            Handle()
            content
        }
        .contentShape(.rect)
        .draggable(payload) {
            preview.padding(.horizontal, 10).padding(.vertical, 6)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            return withAnimation(reduceMotion ? nil : .snappy) { drop(item) }
        } isTargeted: {
            targeted = $0
        }
        .background(.tint.opacity(targeted ? 0.18 : 0), in: .rect(cornerRadius: 6).inset(by: -4))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: targeted)
    }
}

extension Binding {
    /// On while `element` is not in the set: the layout stores what is hidden or left out.
    func excludes<Element>(_ element: Element) -> Binding<Bool> where Value == Set<Element> {
        Binding<Bool> {
            !wrappedValue.contains(element)
        } set: { shown in
            if shown { wrappedValue.remove(element) } else { wrappedValue.insert(element) }
        }
    }
}

/// The grip a reorderable row is dragged by; hidden, it keeps a fixed row's label in line.
private struct Handle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
    }
}

/// Icons in one fixed-width column, so titles line up whatever the symbol's width.
private struct RowLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.frame(width: 20)
            configuration.title
        }
    }
}
