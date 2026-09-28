import SwiftUI

@main
struct ContribusageApp: App {
    // Mock data until the coordinator feeds `AppState` (T-2.6).
    @State private var appState = AppState.mock()

    var body: some Scene {
        MenuBarExtra("contribusage", systemImage: "gauge.with.dots.needle.33percent") {
            PopoverView().environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
