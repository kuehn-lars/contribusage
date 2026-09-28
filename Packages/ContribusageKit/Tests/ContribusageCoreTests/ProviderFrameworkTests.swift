import ContribusageCore
import ContribusageTestSupport
import Foundation
import Testing

/// SPEC §16.4, US-11: the deliberately un-Claude-like `FakeProvider` passes the shared suite.
@Test func fakeProviderPassesTheConformanceSuite() async {
    let fileEvents = FakeFileEvents()
    await ProviderConformance.check(
        FakeProvider(fileEvents: fileEvents),
        neverFinishing: FakeProvider(fetch: {
            try await Task.sleep(for: .seconds(3600))
            throw SourceError.timedOut
        }),
        failing: FakeProvider(fetch: { throw SourceError.io("disk gone") }),
        fileEvents: fileEvents
    )
}

/// A provider needs only the wirings for the capabilities it has.
@Test func activityOnlyProviderPassesTheConformanceSuite() async {
    let fileEvents = FakeFileEvents()
    await ProviderConformance.check(
        ActivityOnlyProvider(base: FakeProvider(fileEvents: fileEvents)), fileEvents: fileEvents)
}

/// The suite is only worth running if it can fail.
@Test func conformanceSuiteRejectsABrokenProvider() async {
    await withKnownIssue {
        await ProviderConformance.check(
            FakeProvider(id: ProviderID(rawValue: "Not Valid"), fetch: { throw CancellationError() }),
            failing: FakeProvider(fetch: { throw URLError(.notConnectedToInternet) })
        )
    }
}

private struct ActivityOnlyProvider: UsageProvider {
    let base: FakeProvider
    var descriptor: ProviderDescriptor {
        ProviderDescriptor(
            id: base.descriptor.id, displayName: "Activity Only", symbolName: "chart.bar", capabilities: .activity,
            tokenCategories: [.input], limitsPolicy: nil
        )
    }
    var limits: (any LimitsSource)? { nil }
    var activity: (any ActivitySource)? { base.activity }
    func detectAvailability() async -> ProviderAvailability { await base.detectAvailability() }
}

private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")
private let c = ProviderID(rawValue: "c")

private func ids(_ providers: [any UsageProvider]) -> [ProviderID] { providers.map(\.descriptor.id) }

/// FR-1, FR-4: registration order is display order, and enabling keeps it.
@Test func registryKeepsRegistrationOrder() async {
    let registry = ProviderRegistry(
        providers: [FakeProvider(id: c), FakeProvider(id: a), FakeProvider(id: b)],
        enabledIDs: [a, b, c],
        time: FakeTimeSource(now: .now)
    )
    #expect(ids(registry.providers) == [c, a, b])
    await registry.setEnabled(c, false)
    await registry.setEnabled(c, true)
    #expect(ids(await registry.enabledProviders()) == [c, a, b])
}

/// FR-2: stored enablement wins; without it (first run) a provider is enabled if it is available.
@Test func registryEnablement() async {
    let providers = { [FakeProvider(id: a), FakeProvider(id: b, availability: .notInstalled)] }

    let firstRun = ProviderRegistry(providers: providers(), enabledIDs: nil, time: FakeTimeSource(now: .now))
    #expect(ids(await firstRun.enabledProviders()) == [a])

    let unprobed = providers()
    let stored = ProviderRegistry(providers: unprobed, enabledIDs: [b], time: FakeTimeSource(now: .now))
    #expect(ids(await stored.enabledProviders()) == [b])
    await stored.setEnabled(b, false)
    #expect(ids(await stored.enabledProviders()).isEmpty)
    #expect(unprobed.map(\.detections) == [0, 0])
}

/// FR-3: `available` is kept; anything else is re-detected at most once per minute.
@Test func registryCachesAvailability() async {
    let time = FakeTimeSource(now: .now)
    let provider = FakeProvider(id: a, availability: .notSignedIn)
    let registry = ProviderRegistry(providers: [provider], enabledIDs: [a], time: time)

    #expect(await registry.availability(of: provider) == .notSignedIn)
    time.advance(by: .seconds(59))
    #expect(await registry.availability(of: provider) == .notSignedIn)
    #expect(provider.detections == 1)

    provider.availability = .available(version: "2.0")
    time.advance(by: .seconds(1))
    #expect(await registry.availability(of: provider) == .available(version: "2.0"))
    #expect(provider.detections == 2)

    provider.availability = .notInstalled
    time.advance(by: .seconds(3600))
    #expect(await registry.availability(of: provider) == .available(version: "2.0"))
    #expect(provider.detections == 2)
}
