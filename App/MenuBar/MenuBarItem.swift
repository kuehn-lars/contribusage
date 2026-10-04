import AppKit
import ContribusageCore
import SwiftUI

/// SPEC §11.1, FR-51: the label in the chosen style and tint, re-read every minute for staleness and resets.
/// A `TimelineView` in a `MenuBarExtra` label makes SwiftUI request label updates in an endless loop, so a task ticks.
struct MenuBarItem: View {
    @Environment(AppState.self) private var appState
    @State private var now = Date.now

    var body: some View {
        let image = appState.menuBarImage(at: now)
        Image(nsImage: image)
            .accessibilityLabel(image.accessibilityDescription ?? "contribusage")
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    now = .now
                }
            }
    }
}

extension AppState {
    /// The label as drawn; `style` overrides the saved one for the previews in Settings.
    func menuBarImage(at now: Date, style: MenuBarStyle? = nil) -> NSImage {
        let style = style ?? menuBarStyle
        let label = menuBarLabel(at: now)
        let days = HeatmapLayer.days(through: now, calendar: .current)
        // The current week and the two before it, from Sunday (`days` ends today).
        let shown = days.suffix(14 + Calendar.current.component(.weekday, from: now))
        let levels = { (source: BlockID) in
            let layer = self.layer(source, days: days, at: now)?.layer
            return shown.map { layer?.levels[$0] ?? 0 }
        }
        // The label's source takes the tint; the other layers keep their hues (SPEC §11.4).
        let layers = menuBarHeatmapSources(label, style: style).map { source in
            MenuBarArt.Layer(
                levels: levels(source),
                color: source == label.source || menuBarTint == .monochrome ? nil : source.hue(in: self))
        }
        return MenuBarArt.image(label, style: style, color: menuBarTintColor(for: label), heatmap: layers)
    }

    /// FR-51: the layers a heatmap style draws, in block order: the label's source for `heatmap`; the shared heatmap's
    /// layers for `sharedHeatmap`, whether or not its block is visible, else the label's source; none for the others.
    func menuBarHeatmapSources(_ label: MenuBarLabel, style: MenuBarStyle) -> [BlockID] {
        let own = label.source.map { [$0] } ?? []
        switch style {
        case .heatmap: return own
        case .sharedHeatmap: return heatmapSources.isEmpty ? own : heatmapSources
        default: return []
        }
    }

    /// FR-51: `nil` for monochrome; usage follows SPEC §11.4's levels.
    private func menuBarTintColor(for label: MenuBarLabel) -> NSColor? {
        switch menuBarTint {
        case .monochrome: nil
        case .accent: .controlAccentColor
        case .usage: label.source != .github && (label.meter ?? 0) >= 0.7 ? .systemOrange : .controlAccentColor
        case .custom: NSColor(hex: menuBarColor)
        case .provider:
            label.source?.hue(in: self) ?? .controlAccentColor
        }
    }
}

extension BlockID {
    /// A source's heatmap hue (SPEC §11.4); `nil` for the heatmap block.
    fileprivate func hue(in appState: AppState) -> NSColor? {
        switch self {
        case .provider(let id): NSColor(appState.group(id).descriptor.heatmapHue.color)
        case .github: .systemGreen
        case .heatmap: nil
        }
    }
}

extension NSColor {
    /// `RRGGBB` in sRGB; `nil` for anything else.
    convenience init?(hex: String) {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// `RRGGBB` in sRGB.
    var hex: String {
        let rgb = usingColorSpace(.sRGB) ?? self
        return String(
            format: "%02X%02X%02X", Int(round(rgb.redComponent * 255)), Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255)))
    }
}
