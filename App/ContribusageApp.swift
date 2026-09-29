import SwiftUI

@main
struct ContribusageApp: App {
    @State private var appState = AppState.live()

    var body: some Scene {
        MenuBarExtra("contribusage", systemImage: "gauge.with.dots.needle.33percent") {
            PopoverView().environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
