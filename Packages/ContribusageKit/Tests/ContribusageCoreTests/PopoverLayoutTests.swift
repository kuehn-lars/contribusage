import ContribusageCore
import Foundation
import Testing

/// SPEC §16.3 popover layout and work follows use (FR-44 to FR-47, §10.8).

private let a = ProviderID(rawValue: "a")
private let b = ProviderID(rawValue: "b")
private let allOn: Set<BlockID> = [.provider(a), .provider(b), .github]

@Test func theDefaultOrderIsProvidersThenHeatmapThenGitHub() {
    #expect(PopoverLayout().blocks(registered: [a, b], on: allOn) == [.provider(a), .provider(b), .heatmap, .github])
}

/// FR-45: a provider missing from the saved order comes last and shows; an unknown one is kept but not shown.
@Test func aNewProviderIsAppendedAndUnknownKeysAreKept() throws {
    let unknown = ProviderID(rawValue: "gone")
    var layout = PopoverLayout()
    layout.order = [.github, .provider(unknown), .provider(a), .heatmap]
    layout.hiddenSections[unknown] = [.limits]
    let saved = try JSONDecoder().decode(PopoverLayout.self, from: JSONEncoder().encode(layout))
    #expect(saved == layout)
    #expect(saved.blocks(registered: [a, b], on: allOn) == [.github, .provider(a), .heatmap, .provider(b)])
}

/// FR-45: blocks persist as the provider ID, `heatmap` or `github`.
@Test func blocksEncodeAsTheirKeys() throws {
    let json = try JSONEncoder().encode([BlockID.provider(a), .heatmap, .github])
    #expect(String(decoding: json, as: UTF8.self) == #"["a","heatmap","github"]"#)
    #expect(try JSONDecoder().decode([BlockID].self, from: json) == [.provider(a), .heatmap, .github])
}

/// FR-44, FR-47: hidden blocks and blocks whose source is off are left out; with none left, nothing shows.
@Test func hiddenAndOffBlocksAreLeftOut() {
    var layout = PopoverLayout()
    layout.hiddenBlocks = [.provider(a)]
    #expect(layout.blocks(registered: [a, b], on: [.provider(a), .github]) == [.heatmap, .github])
    layout.hiddenBlocks = [.github, .heatmap]
    #expect(layout.blocks(registered: [a, b], on: [.provider(b)]) == [.provider(b)])
    #expect(layout.blocks(registered: [a, b], on: [.github]).isEmpty)
}

/// FR-47: the heatmap shows only while a source that is on has a layer in it.
@Test func theHeatmapNeedsALayerThatIsOn() {
    var layout = PopoverLayout()
    layout.outOfHeatmap = [.provider(a)]
    #expect(layout.blocks(registered: [a], on: [.provider(a)]) == [.provider(a)])
    #expect(layout.blocks(registered: [a], on: [.provider(a), .github]) == [.provider(a), .heatmap, .github])
}

/// FR-46: activity runs only for a visible section or a shown layer.
@Test func workFollowsUse() {
    var layout = PopoverLayout()
    layout.hiddenSections[a] = [.activity, .limits]
    layout.outOfHeatmap = [.provider(a)]
    let demand = layout.demand(on: [.provider(a), .provider(b)], menuBar: [])
    #expect(demand.activity == [b])
    #expect(!demand.github)

    layout.outOfHeatmap = []
    #expect(layout.demand(on: [.provider(a)], menuBar: []).activity == [a])
    layout.hiddenBlocks = [.heatmap]
    #expect(layout.demand(on: [.provider(a)], menuBar: []).activity.isEmpty)
    layout.hiddenBlocks = [.heatmap, .provider(b)]
    #expect(layout.demand(on: [.provider(b)], menuBar: []).activity.isEmpty)
}

/// FR-46: a hidden GitHub block still fetches while its layer shows or the menu bar uses it, never while off.
@Test func gitHubRunsWhileSomethingUsesIt() {
    var layout = PopoverLayout()
    layout.hiddenBlocks = [.github]
    #expect(layout.demand(on: [.github], menuBar: []).github)
    layout.outOfHeatmap = [.github]
    #expect(!layout.demand(on: [.github], menuBar: []).github)
    #expect(layout.demand(on: [.github], menuBar: [.github]).github)
    #expect(!layout.demand(on: [], menuBar: [.github]).github)
}
