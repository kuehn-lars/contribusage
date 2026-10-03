import SwiftUI

@main
struct ContribusageApp: App {
    @State private var appState = AppState.live()

    init() {
        // Hover details (heatmap days, reset times; SPEC §11.2) are tooltips; AppKit's default wait is about 1 s.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 200])  // ms
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(appState)
        } label: {
            MenuBarItem().environment(appState)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView().environment(appState) }
    }
}

/// SPEC §11.1: a template symbol and the text of the chosen mode, re-read every minute for staleness and resets.
private struct MenuBarItem: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let label = appState.menuBarLabel(at: context.date)
            HStack(spacing: 4) {
                Image(systemName: label.symbol)
                if !label.text.isEmpty { Text(label.text).monospacedDigit() }
            }
        }
    }
}
