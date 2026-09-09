import AppKit

enum WorkspaceColor: String, CaseIterable {
    case standard, amber, green, teal, blue, indigo, violet

    var title: String { self == .standard ? "Default" : rawValue.capitalized }

    var hue: CGFloat {
        switch self {
        case .standard: return 0
        case .amber: return 0.10
        case .green: return 0.36
        case .teal: return 0.48
        case .blue: return 0.59
        case .indigo: return 0.66
        case .violet: return 0.76
        }
    }

    var swatch: NSColor {
        self == .standard ? NSColor(white: 0.48, alpha: 1) : NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.85, alpha: 1)
    }

    var darkFill: NSColor {
        // Keep the owner-approved default unchanged.
        self == .standard ? Theme.darkFrame : NSColor(calibratedHue: hue, saturation: 0.28, brightness: 0.12, alpha: 1)
    }

    var lightFill: NSColor {
        self == .standard ? Theme.lightFrame : NSColor(calibratedHue: hue, saturation: 0.045, brightness: 0.97, alpha: 1)
    }
}

@MainActor
final class WorkspaceColorButton: NSButton {
    let color: WorkspaceColor
    var onChoose: (() -> Void)?
    init(color: WorkspaceColor) {
        self.color = color
        super.init(frame: .zero)
        isBordered = false
        title = ""
        toolTip = color.title
        setAccessibilityLabel("App color: \(color.title)")
        target = self
        action = #selector(choose)
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 32).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilityValue() -> Any? { state == .on ? 1 : 0 }
    @objc private func choose() { onChoose?() }
    override func draw(_ dirtyRect: NSRect) {
        color.swatch.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 6, dy: 6)).fill()
        if state == .on || isHighlighted {
            NSColor.labelColor.withAlphaComponent(0.65).setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
            ring.lineWidth = 1
            ring.stroke()
        }
    }
}
