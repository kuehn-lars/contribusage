import ContribusageCore
import SwiftUI

/// SPEC §11.6 Popover tab (FR-44, FR-48, FR-49, US-13): every block in popover order, reordered by drag. The open
/// popover follows each change at once through `AppState.layout`.
// ponytail: the style picker's legend preview comes with the layer hues in T-5.16.
struct PopoverTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let blocks = appState.layout.arranged(registered: appState.providers.map(\.id))
        Form {
            Section {
                ForEach(blocks, id: \.self) { block in
                    BlockRow(block: block)
                }
                .onMove { from, to in
                    var moved = blocks
                    moved.move(fromOffsets: from, toOffset: to)
                    appState.layout.arrange(moved)
                }
            } header: {
                Text("Blocks")
            } footer: {
                Text("Drag to change the order.").foregroundStyle(.secondary)
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
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One block: its visibility, "In heatmap" for a source with daily data, a provider's sections; greyed out with a note
/// while its source is off.
private struct BlockRow: View {
    let block: BlockID
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        let isOn = appState.isOn(block)
        let (title, symbolName, offNote, capabilities) = details
        VStack(alignment: .leading) {
            Toggle(isOn: $appState.layout.hiddenBlocks.excludes(block)) {
                Label(title, systemImage: symbolName)
                if !isOn { Text(offNote) }
            }
            if capabilities.contains(.activity) {
                Toggle("In heatmap", isOn: $appState.layout.outOfHeatmap.excludes(block)).padding(.leading, 24)
            }
            if case .provider(let id) = block {
                ForEach(SectionKind.allCases.filter { capabilities.contains($0.capability) }, id: \.self) { section in
                    Toggle(section.title, isOn: $appState.layout[shows: section, of: id]).padding(.leading, 24)
                }
            }
        }
        .foregroundStyle(isOn ? .primary : .secondary)
    }

    /// GitHub has daily data like a provider's activity, and no sections.
    private var details: (String, String, LocalizedStringKey, ProviderCapabilities) {
        switch block {
        case .provider(let id):
            let descriptor = appState.group(id).descriptor
            return (
                descriptor.displayName, descriptor.symbolName, "Off: turn it on in Providers.", descriptor.capabilities
            )
        case .heatmap:
            return (String(localized: "Heatmap"), "calendar", "No source that is on is in the heatmap.", [])
        case .github:
            return ("GitHub", "square.grid.3x3.fill", "Off: turn it on in the GitHub tab.", .activity)
        }
    }
}

extension SectionKind {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .limits: "Limits"
        case .activity: "Activity"
        case .insights: "Insights"
        }
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
