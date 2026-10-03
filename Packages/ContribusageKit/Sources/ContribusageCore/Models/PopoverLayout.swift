import Foundation

/// A block of the popover the user can reorder and hide (FR-44). FR-45: persisted as its raw value, the provider ID,
/// `heatmap` or `github`; `ProviderRegistry` keeps providers off the last two.
public enum BlockID: RawRepresentable, Hashable, Sendable, Codable {
    case provider(ProviderID)
    case heatmap
    case github

    public init(rawValue: String) {
        switch rawValue {
        case "heatmap": self = .heatmap
        case "github": self = .github
        default: self = .provider(ProviderID(rawValue: rawValue))
        }
    }

    public var rawValue: String {
        switch self {
        case .provider(let id): id.rawValue
        case .heatmap: "heatmap"
        case .github: "github"
        }
    }
}

/// A provider group's sections, in their fixed order (FR-44).
public enum SectionKind: String, Sendable, Codable, CaseIterable {
    case limits, activity, insights

    /// The capability a provider declares for this section.
    public var capability: ProviderCapabilities {
        switch self {
        case .limits: .limits
        case .activity: .activity
        case .insights: .insights
        }
    }
}
public enum HeatmapStyle: String, Sendable, Codable { case combined, stacked }

/// What must run besides the limits of every provider that is on (FR-46).
public struct Demand: Sendable, Equatable {
    public var activity: Set<ProviderID>
    public var github: Bool
}

/// The popover's arrangement (FR-44, FR-45), saved by the app in UserDefaults. The default shows everything.
public struct PopoverLayout: Sendable, Codable, Equatable {
    /// Saved order; may name providers that are not registered, which are kept and ignored (FR-45).
    public var order: [BlockID] = []
    public var hiddenBlocks: Set<BlockID> = []
    public var hiddenSections: [ProviderID: Set<SectionKind>] = [:]
    /// A provider group's saved section order (ADR-034); sections missing from it follow in default order.
    public var sectionOrder: [ProviderID: [SectionKind]] = [:]
    /// `.provider(_)` or `.github`.
    public var outOfHeatmap: Set<BlockID> = []
    public var heatmapStyle: HeatmapStyle = .combined

    public init() {}

    /// Whether a provider group shows a section (FR-44); showing every section again drops the provider's entry.
    public subscript(shows section: SectionKind, of provider: ProviderID) -> Bool {
        get { !hiddenSections[provider, default: []].contains(section) }
        set {
            var hidden = hiddenSections[provider, default: []]
            if newValue { hidden.remove(section) } else { hidden.insert(section) }
            hiddenSections[provider] = hidden.isEmpty ? nil : hidden
        }
    }

    /// Visible blocks in order, given the registry order and the sources that are on (FR-44, FR-47).
    public func blocks(registered: [ProviderID], on: Set<BlockID>) -> [BlockID] {
        arranged(registered: registered).filter { !hiddenBlocks.contains($0) && isOn($0, on: on) }
    }

    /// Every registered block in order, hidden or off ones included, as the Popover tab lists them. Blocks missing from
    /// `order` follow in default order: providers, heatmap, GitHub (FR-45).
    public func arranged(registered: [ProviderID]) -> [BlockID] {
        (registered.map(BlockID.provider) + [.heatmap, .github]).ordered(by: order)
    }

    /// Puts `block` in `target`'s place among the registered blocks, as a drop in the Popover tab does (FR-44). Saved
    /// keys of unregistered providers follow them (FR-45).
    public mutating func move(_ block: BlockID, to target: BlockID, registered: [ProviderID]) {
        var blocks = arranged(registered: registered)
        blocks.move(block, to: target)
        order = blocks + order.filter { !blocks.contains($0) }
    }

    /// A provider group's sections in order, hidden ones included (FR-44, ADR-034).
    public func sections(of provider: ProviderID) -> [SectionKind] {
        SectionKind.allCases.ordered(by: sectionOrder[provider, default: []])
    }

    /// The sections a provider group shows, in order (FR-31, FR-44).
    public func shownSections(of provider: ProviderID) -> [SectionKind] {
        sections(of: provider).filter { self[shows: $0, of: provider] }
    }

    /// Puts `section` in `target`'s place within the provider's group, as a drop in the Popover tab does (ADR-034).
    public mutating func move(_ section: SectionKind, to target: SectionKind, of provider: ProviderID) {
        var sections = sections(of: provider)
        sections.move(section, to: target)
        sectionOrder[provider] = sections
    }

    /// Whether a block's source is on; the heatmap's while one of its layers is (FR-47).
    public func isOn(_ block: BlockID, on: Set<BlockID>) -> Bool {
        block == .heatmap ? on.contains { !outOfHeatmap.contains($0) } : on.contains(block)
    }

    /// The heatmap's layers in block order (FR-48, FR-49): every source that is on and in the heatmap, hidden blocks
    /// included; `sources` are the providers with daily data, in registry order.
    public func heatmapLayers(sources: [ProviderID], on: Set<BlockID>) -> [BlockID] {
        arranged(registered: sources).filter { $0 != .heatmap && on.contains($0) && !outOfHeatmap.contains($0) }
    }

    /// What must run (FR-46): a provider's activity while its section or its layer shows, GitHub while its block or
    /// layer shows or the menu bar uses it. Limits need no demand: they run while their provider is on, because
    /// notifications use them.
    public func demand(on: Set<BlockID>, menuBar: Set<BlockID>) -> Demand {
        let providers = on.compactMap { if case .provider(let id) = $0 { id } else { nil } }
        let activity = providers.filter {
            !hiddenBlocks.contains(.provider($0)) && self[shows: .activity, of: $0]
                || inShownHeatmap(.provider($0))
        }
        let github =
            on.contains(.github)
            && (!hiddenBlocks.contains(.github) || inShownHeatmap(.github) || menuBar.contains(.github))
        return Demand(activity: Set(activity), github: github)
    }

    private func inShownHeatmap(_ block: BlockID) -> Bool {
        !hiddenBlocks.contains(.heatmap) && !outOfHeatmap.contains(block)
    }
}

extension Array where Element: Equatable {
    /// The elements `saved` names, in its order, then the others in theirs; `saved`'s unknown entries are skipped.
    fileprivate func ordered(by saved: [Element]) -> [Element] {
        saved.filter(contains) + filter { !saved.contains($0) }
    }

    /// Puts `element` in `target`'s place; the elements between shift by one.
    fileprivate mutating func move(_ element: Element, to target: Element) {
        guard let from = firstIndex(of: element), let to = firstIndex(of: target) else { return }
        insert(remove(at: from), at: to)
    }
}
