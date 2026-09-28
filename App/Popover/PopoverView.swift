import AppKit
import SwiftUI

/// SPEC §11.2: provider groups, GitHub, footer (FR-31).
struct PopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 0) {
                // Many providers scroll; GitHub and the footer stay put.
                // ponytail: fixed allowance for GitHub and footer; measure them if it ever clips.
                ViewThatFits(in: .vertical) {
                    groups
                    ScrollView { groups }
                }
                .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 250)
                GitHubSection(state: appState.github).padding(12)
                Divider()
                Footer().padding(8)
            }
            .environment(\.now, context.date)
        }
        .frame(width: 360)
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
    var body: some View {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") {}  // FR-32, wired with the coordinator (T-2.6)
                .keyboardShortcut("r")
            Spacer()
            Button("Quit", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}
