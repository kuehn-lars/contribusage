import AppKit
import SwiftUI

/// SPEC §11.2: the blocks in the configured order, then the footer (FR-31, FR-44).
struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var groupsHeight: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                // Many providers scroll; the footer stays put. The scroll view exists only while the blocks overflow,
                // since VoiceOver on macOS stops at a scroll area until the user interacts with it; it takes the cap as
                // its height because the menu bar window gives it none.
                // ponytail: fixed allowance for the footer; measure it if it ever clips. Crossing the cap rebuilds the
                // blocks and resets their view state (Insights collapses); keep one identity if it bites.
                let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 250
                let measuredGroups = groups.onGeometryChange(for: CGFloat.self, of: \.size.height) {
                    groupsHeight = $0
                }
                if groupsHeight > maxHeight {
                    ScrollView { measuredGroups }.frame(height: maxHeight)
                } else {
                    measuredGroups
                }
                if appState.blocks.isEmpty {
                    NothingToShow().padding(12)
                    Divider()
                }
                Footer().padding(8)
            }
            .environment(\.now, context.date)
        }
        // No background of its own: the window's Liquid Glass follows the system's clear or tinted setting.
        .frame(width: 360)
        .onAppear { appState.popoverOpened() }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(appState.blocks, id: \.self) { block in
                switch block {
                case .provider(let id): ProviderGroup(group: appState.group(id)).padding(12)
                case .heatmap: HeatmapBlock().padding(12)
                case .github: GitHubSection(state: appState.github).padding(12)
                }
                Divider()
            }
        }
    }
}

/// FR-47, US-13: no visible block has a source that is on.
private struct NothingToShow: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Nothing to show").foregroundStyle(.secondary)
            SettingsButton(title: "Open Settings…", tab: .popover)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Footer: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") { appState.refresh() }  // FR-32
                .keyboardShortcut("r").help("Refresh")
            Spacer()
            SettingsButton(title: "Settings", systemImage: "gearshape", tab: .general).keyboardShortcut(",")
                .help("Settings")
            Spacer()
            Button("Copy", systemImage: "doc.on.doc", action: appState.copyStatistics)  // FR-42
                .help("Copy statistics")
            Spacer()
            Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q").help("Quit")
        }
        // Icons with tooltips: the labels do not fit 360 pt in every language. VoiceOver still reads the titles.
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(.borderless)
    }
}
