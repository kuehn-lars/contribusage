import ContribusageClaudeCode
import ContribusageCore
import SwiftUI

/// SPEC §11.6 Providers tab: one section per registered provider (FR-1 order), Claude Code's with its own rows.
struct ProvidersTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            ForEach(appState.registry?.providers ?? [], id: \.descriptor.id) { provider in
                ProviderSection(provider: provider)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProviderSection: View {
    let provider: any UsageProvider
    @Environment(AppState.self) private var appState
    @State private var availability: ProviderAvailability?
    @State private var confirmingDeletion = false
    @State private var deletionError: String?

    var body: some View {
        let descriptor = provider.descriptor
        let enabled = appState.enabledIDs.contains(descriptor.id)
        Section {
            Toggle(
                isOn: Binding(get: { enabled }, set: { on in Task { await appState.setEnabled(descriptor.id, on) } })
            ) {
                Label(descriptor.displayName, systemImage: descriptor.symbolName)
                Text(availability.map(Self.text) ?? String(localized: "Checking…"))
            }
            if let claudeCode = provider as? ClaudeCodeProvider {
                ClaudeCodeRows(provider: claudeCode, descriptor: descriptor)
            }
            LabeledContent {
                Button("Delete…", role: .destructive) { confirmingDeletion = true }.disabled(enabled)
            } label: {
                Text("Data")
                Text(enabled ? "Turn \(descriptor.displayName) off to delete its data." : "History and caches")
                if let deletionError { Text(deletionError).foregroundStyle(.red) }
            }
            .confirmationDialog(
                "Delete all data for \(descriptor.displayName)?", isPresented: $confirmingDeletion
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await appState.deleteData(of: descriptor.id)
                            deletionError = nil
                        } catch {
                            deletionError = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Its usage history cannot be restored.")
            }
        }
        // FR-3: the registry runs detection at most once per minute while not available.
        .task { availability = await appState.registry?.availability(of: provider) }
    }

    private static func text(_ availability: ProviderAvailability) -> String {
        switch availability {
        case .available: String(localized: "Available")
        case .notInstalled: String(localized: "Not installed")
        case .notSignedIn: String(localized: "Not signed in")
        case .unsupportedPlan(let note): note
        case .unknown(let reason): reason
        }
    }
}

/// The located `claude`, its override and the probe interval (SPEC §11.6, FR-6).
private struct ClaudeCodeRows: View {
    let provider: ClaudeCodeProvider
    let descriptor: ProviderDescriptor
    @AppStorage("provider.claude-code.pathOverride") private var pathOverride: String?
    @State private var lookup = Lookup.searching
    @State private var testResult: String?
    @State private var choosingPath = false

    var body: some View {
        LabeledContent("claude") {
            switch lookup {
            case .searching: ProgressView().controlSize(.small)
            case .notFound: Text("Not found")
            case .found(let claude):
                VStack(alignment: .trailing) {
                    Text(claude.executable.path(percentEncoded: false)).textSelection(.enabled)
                    Text("\(claude.version) · \(Self.text(claude.kind))")
                }
            }
        }
        LabeledContent {
            HStack {
                if pathOverride != nil { Button("Clear") { set(nil) } }
                Button("Choose…") { choosingPath = true }
                Button("Test", action: test).disabled(pathOverride == nil)
            }
        } label: {
            Text("Override")
            Text(pathOverride ?? String(localized: "None"))
            if let testResult { Text(testResult) }
        }
        .fileImporter(isPresented: $choosingPath, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { set(url.path(percentEncoded: false)) }
        }
        IntervalPicker(
            "Check limits every", key: "provider.claude-code.probeInterval", policy: descriptor.limitsPolicy!,
            choices: [5, 10, 15, 30, 60]
        )
        .task { lookup = Lookup(await provider.located()) }
    }

    private enum Lookup {
        case searching, notFound
        case found(ClaudeLocator.Found)

        init(_ claude: ClaudeLocator.Found?) { self = claude.map(Lookup.found) ?? .notFound }
    }

    private func set(_ path: String?) {
        pathOverride = path
        testResult = nil
    }

    /// The provider locates again when the override changed; an override that fails `--version` falls through (FR-6).
    private func test() {
        testResult = String(localized: "Testing…")
        Task {
            let claude = await provider.located()
            lookup = Lookup(claude)
            testResult =
                switch claude {
                case let claude? where claude.executable.path(percentEncoded: false) == pathOverride:
                    String(localized: "Works: \(claude.version)")
                case let claude?:
                    String(localized: "Doesn't run; using \(claude.executable.path(percentEncoded: false))")
                case nil: String(localized: "Doesn't run, and no other claude was found")
                }
        }
    }

    private static func text(_ kind: ClaudeLocator.ExecutableKind) -> String {
        switch kind {
        case .machOArm64: String(localized: "Apple silicon")
        case .machOIntel: String(localized: "Intel, needs Rosetta")
        case .script: String(localized: "Script")
        case .unknown: String(localized: "Unknown type")
        }
    }
}
