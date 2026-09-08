import AppKit

/// Resolves layer colors again when macOS appearance changes, including System mode.
@MainActor
class AppearancePanel: NSView {
    var darkFill = NSColor(red: 0.064, green: 0.068, blue: 0.072, alpha: 1)
    var lightFill = NSColor(white: 0.94, alpha: 1)
    var fillOpacity: CGFloat = 1 { didSet { if oldValue != fillOpacity { updateColors() } } }
    override var isOpaque: Bool { fillOpacity == 1 && (layer?.cornerRadius ?? 0) == 0 }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    func updateColors() {
        wantsLayer = true
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = (dark ? darkFill : lightFill).withAlphaComponent(fillOpacity).cgColor
        guard layer?.backgroundColor != color else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = color
        CATransaction.commit()
        PerformanceDiagnostics.record("panelColorUpdates")
        needsDisplay = true
    }
}
