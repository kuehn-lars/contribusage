import AppKit
import ContribusageCore
import SwiftUI

extension EnvironmentValues {
    /// Ticks once per minute while the popover is visible (SPEC §11.2).
    @Entry var now = Date.now
}

/// Draws one source in every state of SPEC §11.3 around its loaded content.
struct SectionStateView<Value: Sendable & Codable, Content: View>: View {
    let state: SourceState<Value>
    let displayName: String
    /// `nil` for sources that never go stale (activity).
    var staleAfter: Duration?
    /// The skeleton of the first load is this value, redacted.
    let placeholder: Value
    /// `nil` hides Retry, for sources nothing refreshes yet.
    var retry: (() -> Void)?
    @ViewBuilder let content: (Value) -> Content
    @Environment(\.now) private var now

    var body: some View {
        switch state {
        case .notConfigured(let reason):
            NotConfiguredView(reason: reason, displayName: displayName)
        case .loading(nil):
            content(placeholder).redacted(reason: .placeholder)
        case .loading(let previous?):
            content(previous.value)
        case .loaded(let snapshot):
            // The age is always in the section header (`SectionHeader`), so stale only dims.
            let stale = staleAfter.map { snapshot.isStale(at: now, after: $0) } ?? false
            content(snapshot.value).opacity(stale ? 0.5 : 1)
        case .failed(let error, let previous):
            if let previous { content(previous.value).opacity(0.5) }
            ErrorLine(error: error, displayName: displayName, retry: retry)
        }
    }
}

struct NotConfiguredView: View {
    let reason: NotConfiguredReason
    let displayName: String

    var body: some View {
        switch reason {
        case .providerDisabled:
            EmptyView()
        case .toolNotInstalled:
            HStack {
                Text("\(displayName) not found")
                Spacer()
                Button("Locate…") {}  // T-5.2
            }
        case .unsupportedPlan(let note):
            Text(note).foregroundStyle(.secondary)
        case .noLocalData:
            Text("No \(displayName) sessions found on this Mac").foregroundStyle(.secondary)
        case .githubTokenMissing:
            SettingsButton(title: "Connect GitHub")
        }
    }
}

struct SettingsButton: View {
    let title: LocalizedStringKey
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(title) {
            // SPEC §20: an agent app must activate itself, or Settings opens behind other apps.
            NSApp.activate()
            openSettings()
        }
    }
}

struct ErrorLine: View {
    let error: SourceError
    let displayName: String
    let retry: (() -> Void)?

    var body: some View {
        HStack {
            let message = error.message(displayName: displayName)
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .help(message)
            Spacer()
            // A 401 repeats until the token changes (SPEC §12), so it offers the token instead of Retry.
            if case .unauthorized = error {
                SettingsButton(title: "Change token…")
            } else if let retry {
                Button("Retry", action: retry)
            }
        }
        .font(.caption)
        .controlSize(.small)
        if case .unparseable(let raw) = error {
            DisclosureGroup("Show raw output") {
                ScrollView { Text(raw).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 120)
            }
            .font(.caption)
        }
    }
}

/// Symbol, title, an optional subtitle and the age of the section's data (SPEC §11.2).
struct SectionHeader: View {
    let title: String
    let symbolName: String
    var subtitle: String?
    let fetchedAt: Date?

    var body: some View {
        HStack {
            Label(title, systemImage: symbolName).font(.headline)
            if let subtitle { Text(subtitle).foregroundStyle(.secondary) }
            Spacer()
            if let fetchedAt { AgeText(fetchedAt: fetchedAt).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// "updated just now", "updated 2 min ago" (SPEC §11.5).
struct AgeText: View {
    let fetchedAt: Date
    @Environment(\.now) private var now

    var body: some View {
        let age = now.timeIntervalSince(fetchedAt)
        if age < 60 {
            Text("updated just now")
        } else {
            let units = Duration.seconds(age).formatted(
                .units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1))
            Text("updated \(units) ago")
        }
    }
}

extension SourceError {
    /// SPEC §13, shared by the popover's error lines and Settings.
    func message(displayName: String) -> String {
        switch self {
        case .toolNotFound: "\(displayName) wasn't found"
        case .notLoggedIn: "\(displayName) isn't logged in"
        case .unsupportedPlan(let note): note
        case .timedOut: "\(displayName) didn't answer in time"
        case .processFailed(let exitCode, _): "Exited with code \(exitCode)"
        case .unparseable: "Couldn't read the usage output"
        case .offline: "Offline"
        case .tokenMissing: "No \(displayName) token saved"
        case .unauthorized: "\(displayName) token is invalid or expired"
        case .rateLimited(let until): "Rate limited until \(until.formatted(date: .omitted, time: .shortened))"
        case .http(let status): "Server error \(status)"
        case .decoding(let message), .io(let message): message
        case .providerSpecific: "Something went wrong with \(displayName)"
        }
    }
}
