import SwiftUI

@main
struct ContribusageApp: App {
    var body: some Scene {
        MenuBarExtra("contribusage", systemImage: "gauge.with.dots.needle.33percent") {
            Button("Quit contribusage") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
