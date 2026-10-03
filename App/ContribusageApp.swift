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
