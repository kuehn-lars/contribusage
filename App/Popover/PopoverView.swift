import AppKit
import SwiftUI

/// SPEC §11.2: provider groups, GitHub, footer (FR-31).
struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var groupsHeight: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                // Many providers scroll; GitHub and the footer stay put. The scroll view takes the groups' measured
                // height: in the menu bar window it has no height of its own, and `ViewThatFits` fell back to it.
                // ponytail: fixed allowance for GitHub and footer; measure them if it ever clips.
                ScrollView {
                    groups.onGeometryChange(for: CGFloat.self, of: \.size.height) { groupsHeight = $0 }
                }
                .frame(height: min(groupsHeight, (NSScreen.main?.visibleFrame.height ?? 800) - 250))
                GitHubSection(state: appState.github).padding(12)
                Divider()
                Footer().padding(8)
            }
            .environment(\.now, context.date)
        }
        .frame(width: 360)
        .onAppear { appState.popoverOpened() }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(appState.providers) { group in
                ProviderGroup(group: group).padding(12)
                Divider()
            }
        }
    }
}

private struct Footer: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") { appState.refresh() }  // FR-32
                .keyboardShortcut("r")
            Spacer()
            Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}
