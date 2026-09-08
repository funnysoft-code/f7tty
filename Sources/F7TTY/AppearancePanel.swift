import AppKit

/// Resolves layer colors again when macOS appearance changes, including System mode.
@MainActor
class AppearancePanel: NSView {
    var darkFill = NSColor(red: 0.064, green: 0.068, blue: 0.072, alpha: 1)
    var lightFill = NSColor(white: 0.94, alpha: 1)
    var fillOpacity: CGFloat = 1 { didSet { updateColors() } }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    func updateColors() {
        wantsLayer = true
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? darkFill : lightFill).withAlphaComponent(fillOpacity).cgColor
        needsDisplay = true
    }
}
