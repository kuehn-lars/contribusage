import AppKit
import ContribusageCore

/// SPEC §11.1, FR-51: the menu bar label as one image. It is not a template: the drawing handler runs whenever the
/// status item draws, in its appearance, so `labelColor` follows a light or dark menu bar and the tint stays in color.
enum MenuBarArt {
    /// Points: the status item centers the image vertically.
    private static let height: CGFloat = 18
    private static let gap: CGFloat = 4
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    /// A heatmap layer: its levels (0 to 4) of the last three weeks, oldest first, from a Sunday through today, and
    /// its color; `nil` takes the meter's.
    struct Layer {
        var levels: [Int]
        var color: NSColor?
    }

    /// `color` is the tint, `nil` for monochrome; `heatmap` holds the layers in block order.
    static func image(_ label: MenuBarLabel, style: MenuBarStyle, color: NSColor?, heatmap: [Layer] = []) -> NSImage {
        let glyph = glyph(style, label, color)
        let text = style == .text ? label.title + (label.text.isEmpty ? "" : " ") : ""
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font])
        if style != .ring {
            attributed.append(NSAttributedString(string: label.text, attributes: [.font: font, .kern: -0.1]))
        }
        let badge = label.badge.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        let badgeWidth = badge.map { $0.size.width + gap } ?? 0
        let textWidth = attributed.length == 0 ? 0 : ceil(attributed.size().width)
        let glyphWidth = glyph.width + (glyph.width > 0 && textWidth > 0 ? gap : 0)
        let size = NSSize(width: max(badgeWidth + glyphWidth + textWidth, 1), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            // A heatmap is history, not the limit: it keeps its hues, and red next to GitHub's green would fail the most
            // common color blindness (ADR-032). Its value turns red instead.
            let isHeatmap = style == .heatmap || style == .sharedHeatmap
            let fill = paint(label, isHeatmap ? nil : color, base: color)
            var x: CGFloat = 0
            if let badge {
                badge.tinted(.labelColor).draw(
                    at: NSPoint(x: 0, y: (height - badge.size.height) / 2), from: .zero,
                    operation: .sourceOver, fraction: 1)
                x += badgeWidth
            }
            glyph.draw(x, fill, heatmap)
            x += glyphWidth
            // The value takes the tint in the text style; elsewhere the glyph carries it.
            let value = NSMutableAttributedString(attributedString: attributed)
            value.addAttribute(
                .foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: value.length))
            let critical = color != nil && (label.meter ?? 0) >= 0.9
            if style == .text && color != nil || isHeatmap && critical {
                let range = NSRange(location: (text as NSString).length, length: (label.text as NSString).length)
                value.addAttribute(.foregroundColor, value: paint(label, color), range: range)
            }
            value.draw(at: NSPoint(x: x, y: (height - value.size().height) / 2 + 0.5))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = [label.title, label.text].filter { !$0.isEmpty }.joined(separator: " ")
        return image
    }

    /// The meter's color: red from 90 % in any tint but monochrome (SPEC §11.4), half strength while stale. Without
    /// `color`, `base` (the tint never turned red) or else `labelColor`.
    private static func paint(_ label: MenuBarLabel, _ color: NSColor?, base: NSColor? = nil) -> NSColor {
        let shown = color.map { (label.meter ?? 0) >= 0.9 ? .systemRed : $0 } ?? base ?? .labelColor
        return label.isStale ? shown.withAlphaComponent(0.5) : shown
    }

    private struct Glyph {
        let width: CGFloat
        let draw: (_ x: CGFloat, _ fill: NSColor, _ heatmap: [Layer]) -> Void
    }

    /// Computed: a derived color resolves in the appearance it is made in, so it must be made while drawing.
    private static var track: NSColor { NSColor.labelColor.withAlphaComponent(0.25) }

    private static func glyph(_ style: MenuBarStyle, _ label: MenuBarLabel, _ color: NSColor?) -> Glyph {
        let meter = label.meter ?? 0
        switch style {
        case .prompt:
            // The mark: a prompt, then three code lines that the agent "types" as the window fills.
            return Glyph(width: 16) { x, fill, _ in
                let mid = height / 2
                chevron(at: NSPoint(x: x + 1, y: mid + 5.5), size: 2.8).stroked(.labelColor, 1.8)
                let lines = NSBezierPath()
                for (row, (indent, length)) in [(6.7, 9.0), (3.7, 12.0), (3.7, 7.5)].enumerated() {
                    let y = mid + 5.5 - CGFloat(row) * 5.5
                    lines.move(to: NSPoint(x: x + indent, y: y))
                    lines.line(to: NSPoint(x: x + indent + length, y: y))
                }
                lines.stroked(track, 2.2)
                lines.trimmed(to: meter).stroked(fill, 2.2)
            }
        case .rings:
            return Glyph(width: 17) { x, fill, _ in
                let center = NSPoint(x: x + 8.5, y: height / 2)
                ring(center, radius: 7.4, value: meter, fill: fill, width: 2.2)
                if let companion = label.companion {
                    var inner = label
                    inner.meter = companion
                    ring(center, radius: 4.2, value: companion, fill: paint(inner, color), width: 2.2)
                }
            }
        case .ring:
            return Glyph(width: 18) { x, fill, _ in
                let center = NSPoint(x: x + 9, y: height / 2)
                ring(center, radius: 8, value: meter, fill: fill, width: 1.8)
                let value = label.text.split(separator: " · ").first ?? ""
                let digits = value.filter { $0.isNumber || $0 == "<" }
                let number = digits.isEmpty && value.contains("?") ? "?" : String(digits)
                let string = NSAttributedString(
                    string: number,
                    attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: number.count > 2 ? 6.8 : 8.5, weight: .bold),
                        .foregroundColor: NSColor.labelColor, .kern: -0.3,
                    ])
                let size = string.size()
                string.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2 + 0.3))
            }
        case .line:
            return Glyph(width: 28) { x, fill, _ in
                let mid = height / 2
                chevron(at: NSPoint(x: x + 1.5, y: mid), size: 4.5).stroked(.labelColor, 2)
                let line = NSBezierPath()
                line.move(to: NSPoint(x: x + 9.5, y: mid - 4.5))
                line.line(to: NSPoint(x: x + 27, y: mid - 4.5))
                line.stroked(track, 2.4)
                line.trimmed(to: meter).stroked(fill, 2.4)
            }
        case .heatmap, .sharedHeatmap:
            // Rows are weeks, oldest on top; columns are weekdays from Sunday, as in the popover's columns. Shared
            // cells are wider, so two stripes stay apart.
            let cell: CGFloat = style == .heatmap ? 3.6 : 4.2
            let spacing: CGFloat = style == .heatmap ? 1.1 : 1
            return Glyph(width: 7 * cell + 6 * spacing) { x, fill, layers in
                let top = height / 2 + (3 * cell + 2 * spacing) / 2
                let days = layers.map(\.levels.count).max() ?? 0
                for index in 0..<min(days, 21) {
                    let rect = NSRect(
                        x: x + CGFloat(index % 7) * (cell + spacing),
                        y: top - CGFloat(index / 7 + 1) * cell - CGFloat(index / 7) * spacing, width: cell,
                        height: cell)
                    let shape = NSBezierPath(roundedRect: rect, xRadius: 0.9, yRadius: 0.9)
                    // FR-49 Combined: a stripe per layer active that day; none is level 0, a neutral fill.
                    let active = layers.compactMap { layer -> (level: Int, color: NSColor)? in
                        let level = layer.levels.suffix(days).dropFirst(index).first ?? 0
                        return level > 0 ? (level, layer.color ?? fill) : nil
                    }
                    guard !active.isEmpty else {
                        NSColor.labelColor.withAlphaComponent(0.15).setFill()
                        shape.fill()
                        continue
                    }
                    NSGraphicsContext.saveGraphicsState()
                    shape.addClip()
                    let width = cell / CGFloat(active.count)
                    for (stripe, day) in active.enumerated() {
                        // SPEC §11.4: levels 1 to 4 from 40 % to full strength.
                        day.color.withAlphaComponent((label.isStale ? 0.5 : 1) * (0.2 + 0.2 * CGFloat(day.level)))
                            .setFill()
                        NSRect(x: rect.minX + CGFloat(stripe) * width, y: rect.minY, width: width, height: cell).fill()
                    }
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        case .text:
            return Glyph(width: 0) { _, _, _ in }
        }
    }

    private static func chevron(at point: NSPoint, size: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: point.x, y: point.y + size))
        path.line(to: NSPoint(x: point.x + size * 1.05, y: point.y))
        path.line(to: NSPoint(x: point.x, y: point.y - size))
        return path
    }

    /// A track and an arc clockwise from 12 o'clock.
    private static func ring(_ center: NSPoint, radius: CGFloat, value: Double, fill: NSColor, width: CGFloat) {
        let circle = NSBezierPath()
        circle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        circle.stroked(track, width)
        guard value > 0 else { return }
        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(value), clockwise: true)
        arc.stroked(fill, width)
    }
}

extension NSBezierPath {
    fileprivate func stroked(_ color: NSColor, _ width: CGFloat) {
        lineWidth = width
        lineCapStyle = .round
        lineJoinStyle = .round
        color.setStroke()
        stroke()
    }

    /// The path's first `fraction` of its length, as straight segments.
    fileprivate func trimmed(to fraction: Double) -> NSBezierPath {
        var segments: [(NSPoint, NSPoint)] = []
        var points = [NSPoint](repeating: .zero, count: 3)
        var last = NSPoint.zero
        let flat = flattened
        for index in 0..<flat.elementCount {
            let kind = flat.element(at: index, associatedPoints: &points)
            if kind == .lineTo { segments.append((last, points[0])) }
            if kind == .moveTo || kind == .lineTo { last = points[0] }
        }
        let length = { (segment: (NSPoint, NSPoint)) in hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y) }
        var left = segments.map(length).reduce(0, +) * fraction
        let path = NSBezierPath()
        for segment in segments where left > 0 {
            let part = min(left / length(segment), 1)
            path.move(to: segment.0)
            path.line(
                to: NSPoint(
                    x: segment.0.x + (segment.1.x - segment.0.x) * part,
                    y: segment.0.y + (segment.1.y - segment.0.y) * part))
            left -= length(segment)
        }
        return path
    }
}

extension NSImage {
    /// A symbol drawn in `color`, resolved when drawn.
    fileprivate func tinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
