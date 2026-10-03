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
/// A `TimelineView` in a `MenuBarExtra` label makes SwiftUI request label updates in an endless loop, so a task ticks.
private struct MenuBarItem: View {
    @Environment(AppState.self) private var appState
    @State private var now = Date.now

    var body: some View {
        let label = appState.menuBarLabel(at: now)
        Image(systemName: label.symbol)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = .now
                }
            }
        if !label.text.isEmpty { Text(label.text).monospacedDigit() }
    }
}
