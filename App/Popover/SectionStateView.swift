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
            ErrorLine(error: error)
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
            Button("Connect GitHub") {}  // T-3.2
        }
    }
}

struct ErrorLine: View {
    let error: SourceError

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle").lineLimit(1)
            Spacer()
            Button("Retry") {}  // wired with the coordinator (T-2.6)
        }
        .font(.caption)
        if case .unparseable(let raw) = error {
            DisclosureGroup("Show raw output") {
                ScrollView { Text(raw).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 120)
            }
            .font(.caption)
        }
    }

    private var message: String {
        switch error {
        case .toolNotFound: "Tool not found"
        case .notLoggedIn: "Not logged in"
        case .timedOut: "Timed out"
        case .processFailed(let exitCode, _): "Exited with code \(exitCode)"
        case .unparseable: "Couldn't read the usage output"
        case .offline: "Offline"
        case .unauthorized: "Token rejected"
        case .rateLimited(let until): "Rate limited until \(until.formatted(date: .omitted, time: .shortened))"
        case .http(let status): "Server error \(status)"
        case .decoding(let message), .io(let message), .providerSpecific(_, let message): message
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
