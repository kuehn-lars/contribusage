import ContribusageCore
import ContribusageGitHub
import ServiceManagement
import SwiftUI

/// SPEC §11.6. The status line bridge (T-6.2) joins its tab with its task.
struct SettingsView: View {
    /// Shared with `SettingsButton`, which opens a given tab.
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            PopoverTab().tabItem { Label("Popover", systemImage: "rectangle.3.group") }.tag(SettingsTab.popover)
            ProvidersTab().tabItem { Label("Providers", systemImage: "square.stack") }.tag(SettingsTab.providers)
            GitHubTab().tabItem { Label("GitHub", systemImage: "square.grid.3x3.fill") }.tag(SettingsTab.github)
            AdvancedTab().tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }.tag(SettingsTab.advanced)
        }
        .frame(width: 460)
    }
}

enum SettingsTab: String {
    case general, popover, providers, github, advanced
}

/// FR-12, FR-13, FR-14, FR-34.
private struct GeneralTab: View {
    @Environment(AppState.self) private var appState
    /// Read from `SMAppService`, never stored (SPEC §10.7); re-read on activation, since System Settings can change it.
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @AppStorage("notifyOnReset") private var notifyOnReset = false
    /// Saved on edits only, so an untouched field keeps the planner's defaults.
    @State private var thresholds = NotificationPlanner.Settings.stored.thresholds.map(String.init)
        .joined(separator: ", ")

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: menuBarMode) {
                    ForEach(appState.menuBarModes, id: \.self) { Text($0.title).tag($0) }
                }
                if appState.providers.count > 1 {
                    Picker("Provider", selection: menuBarProvider) {
                        ForEach(appState.menuBarProviders) { Text($0.descriptor.displayName).tag(Optional($0.id)) }
                    }
                }
            }
            Section {
                Toggle("Launch at login", isOn: launchAtLogin)
                if loginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open System Settings", action: SMAppService.openSystemSettingsLoginItems)
                    } label: {
                        Text("Waiting for approval")
                        Text("Allow contribusage in Login Items.")
                    }
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section {
                TextField("Notify at", text: $thresholds, prompt: Text("80, 95"))
                Toggle("Notify when a window resets", isOn: $notifyOnReset)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Up to three percentages from 50 to 99, separated by commas; others are ignored.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
        .onChange(of: thresholds) {
            // The planner applies the bounds (FR-13), so the field may hold what it ignores.
            NotificationPlanner.Settings.stored.thresholds = thresholds.split { !$0.isNumber }.compactMap { Int($0) }
        }
    }

    /// A saved mode that is not offered shows as the one the label falls back to (FR-12).
    private var menuBarMode: Binding<MenuBarMode> {
        Binding {
            appState.resolvedMenuBarMode
        } set: {
            appState.menuBarMode = $0
        }
    }

    /// Shows the provider the label uses (FR-12).
    private var menuBarProvider: Binding<ProviderID?> {
        Binding {
            appState.shownMenuBarProvider
        } set: {
            appState.menuBarProvider = $0
        }
    }

    /// On while registered, including while it waits for approval. After a failed call it shows the real status.
    private var launchAtLogin: Binding<Bool> {
        Binding {
            loginStatus == .enabled || loginStatus == .requiresApproval
        } set: { on in
            do {
                try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                loginError = nil
            } catch {
                loginError = String(localized: "Couldn't change launch at login: \(error.localizedDescription)")
            }
            loginStatus = SMAppService.mainApp.status
        }
    }
}

extension MenuBarMode {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .primary: "Current session"
        case .weekly: "Weekly limit"
        case .highest: "Highest limit"
        case .githubToday: "GitHub contributions today"
        case .primaryAndGitHub: "Current session and GitHub"
        case .iconOnly: "Icon only"
        }
    }
}

private struct AdvancedTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            LabeledContent("Data folder") {
                Button("Open") { NSWorkspace.shared.open(AppPaths.live.root) }
            }
            LabeledContent {
                Button("Reset", action: appState.resetCaches)
            } label: {
                Text("Caches")
                Text("Fetches every value again; history stays.")
            }
            LabeledContent {
                Button("Copy Diagnostics", action: appState.copyDiagnostics)
            } label: {
                Text("Diagnostics")
                Text("App, Mac and provider status for a bug report; never a token.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// An interval setting of SPEC §11.6, in minutes (§10.7); unset shows the policy's default. A change reschedules at once.
struct IntervalPicker: View {
    let title: LocalizedStringKey
    let choices: [Int]
    @AppStorage private var minutes: Int
    @Environment(AppState.self) private var appState

    init(_ title: LocalizedStringKey, key: String, policy: SchedulePolicy, choices: [Int]) {
        self.title = title
        self.choices = choices
        _minutes = AppStorage(wrappedValue: Int(policy.defaultInterval / .seconds(60)), key)
    }

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(choices, id: \.self) { Text($0 < 60 ? "\($0) min" : "\($0 / 60) h").tag($0) }
        }
        .onChange(of: minutes) { appState.intervalsChanged() }
    }
}
