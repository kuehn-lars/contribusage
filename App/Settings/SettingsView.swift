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
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 460)
    }
}

enum SettingsTab: String {
    case general, popover, providers, github, advanced, about
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
                MenuBarStylePicker()
                Picker("Color", selection: Bindable(appState).menuBarTint) {
                    ForEach(MenuBarTint.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if appState.menuBarTint == .custom {
                    ColorPicker("Custom color", selection: menuBarColor, supportsOpacity: false)
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

    /// FR-51: kept as `RRGGBB`.
    private var menuBarColor: Binding<Color> {
        Binding {
            Color(nsColor: NSColor(hex: appState.menuBarColor) ?? .controlAccentColor)
        } set: {
            appState.menuBarColor = NSColor($0).hex
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

/// FR-51: each style as a tile that shows the label as it would draw now, in the chosen color.
private struct MenuBarStylePicker: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                ForEach(MenuBarStyle.allCases, id: \.self) { style in
                    let selected = appState.menuBarStyle == style
                    Button {
                        appState.menuBarStyle = style
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: appState.menuBarImage(at: .now, style: style))
                                .frame(maxWidth: .infinity, minHeight: 30)
                                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                                }
                            Text(style.title).font(.caption).foregroundStyle(selected ? .primary : .secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

extension MenuBarStyle {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .prompt: "Prompt"
        case .rings: "Rings"
        case .ring: "Ring"
        case .line: "Line"
        case .heatmap: "Heatmap"
        case .sharedHeatmap: "Shared heatmap"
        case .text: "Text"
        }
    }
}

extension MenuBarTint {
    fileprivate var title: LocalizedStringKey {
        switch self {
        case .provider: "Provider color"
        case .usage: "By usage"
        case .accent: "Accent color"
        case .monochrome: "Monochrome"
        case .custom: "Custom"
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

/// SPEC §11.6: the app's icon, version, author and license. The author line is the Info.plist copyright.
private struct AboutTab: View {
    private static let repository = URL(string: "https://github.com/kuehn-lars/contribusage")!

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)
            Text(verbatim: "contribusage").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.versionAndBuild)")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("AI coding tool usage and GitHub contributions in the menu bar.")
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text(Bundle.main.infoString("NSHumanReadableCopyright"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Source Code", destination: Self.repository)
                Link("MIT License", destination: Self.repository.appending(path: "blob/main/LICENSE"))
                Link("Acknowledgements", destination: URL(string: "\(Self.repository)#acknowledgements")!)
            }
            .padding(.top, 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// An interval setting of SPEC §11.6, in minutes (§10.7); unset shows the policy's default. A change reschedules at once.
/// The choices are the steps within the policy's bounds, so a policy change needs no picker change.
struct IntervalPicker: View {
    private static let steps = [1, 2, 5, 10, 15, 30, 60, 120, 240, 360]
    let title: LocalizedStringKey
    let choices: [Int]
    @AppStorage private var minutes: Int
    @Environment(AppState.self) private var appState

    init(_ title: LocalizedStringKey, key: String, policy: SchedulePolicy) {
        let bounds = Int(policy.minimumInterval / .seconds(60))...Int(policy.maximumInterval / .seconds(60))
        self.title = title
        choices = Self.steps.filter(bounds.contains)
        _minutes = AppStorage(wrappedValue: Int(policy.defaultInterval / .seconds(60)), key)
    }

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(choices, id: \.self) { Text($0 < 60 ? "\($0) min" : "\($0 / 60) h").tag($0) }
        }
        .onChange(of: minutes) { appState.intervalsChanged() }
    }
}
