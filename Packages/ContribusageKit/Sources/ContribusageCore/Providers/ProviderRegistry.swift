import Foundation

/// The registered providers in display order (FR-1), which of them are enabled (FR-2) and their cached
/// availability (FR-3).
public actor ProviderRegistry {
    /// Registration order is display order.
    public nonisolated let providers: [any UsageProvider]
    private let time: any TimeSource
    /// `nil` until the first-run default is settled.
    private var enabledIDs: Set<ProviderID>?
    private var lastDetection: [ProviderID: (availability: ProviderAvailability, at: Date)] = [:]
    private static let redetectionInterval: TimeInterval = 60

    /// `enabledIDs` is the stored `enabledProviders` setting, `nil` on first run.
    public init(providers: [any UsageProvider], enabledIDs: Set<ProviderID>?, time: any TimeSource) {
        precondition(Set(providers.map(\.descriptor.id)).count == providers.count, "duplicate provider ID")
        self.providers = providers
        self.enabledIDs = enabledIDs
        self.time = time
    }

    /// In registration order; callers persist their IDs as the `enabledProviders` setting.
    public func enabledProviders() async -> [any UsageProvider] {
        let ids = await settledEnabledIDs()
        return providers.filter { ids.contains($0.descriptor.id) }
    }

    public func setEnabled(_ id: ProviderID, _ enabled: Bool) async {
        var ids = await settledEnabledIDs()
        if enabled { ids.insert(id) } else { ids.remove(id) }
        enabledIDs = ids
    }

    /// `available` is kept for the app's lifetime; any other result is re-detected at most once per minute.
    // ponytail: concurrent callers during a detection each run it; add an in-flight task if detection gets costly.
    public func availability(of provider: any UsageProvider) async -> ProviderAvailability {
        let id = provider.descriptor.id
        if let last = lastDetection[id] {
            if case .available = last.availability { return last.availability }
            if time.now.timeIntervalSince(last.at) < Self.redetectionInterval { return last.availability }
        }
        let availability = await provider.detectAvailability()
        lastDetection[id] = (availability, time.now)
        return availability
    }

    /// The stored setting, or on first run every provider that reports `available`.
    private func settledEnabledIDs() async -> Set<ProviderID> {
        if let enabledIDs { return enabledIDs }
        var available: Set<ProviderID> = []
        for provider in providers {
            if case .available = await availability(of: provider) { available.insert(provider.descriptor.id) }
        }
        let settled = enabledIDs ?? available  // a caller may have settled it during the detections
        enabledIDs = settled
        return settled
    }
}
