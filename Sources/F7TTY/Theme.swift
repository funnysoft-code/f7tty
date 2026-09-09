import AppKit

enum Theme {
    static let titleStripHeight: CGFloat = 30
    static let sessionRowHeight: CGFloat = 28
    static let sidebarDefaultWidth: CGFloat = 300
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarMaxWidth: CGFloat = 520
    static let surfaceInset: CGFloat = 8
    static let contentCornerRadius: CGFloat = 10
    static let rowCornerRadius: CGFloat = 9
    static let chipCornerRadius: CGFloat = 7
    static let overlayCornerRadius: CGFloat = 16
    static let windowMinSize = NSSize(width: 800, height: 600)

    static let darkFrame = NSColor(srgbRed: 0x12 / 255, green: 0x13 / 255, blue: 0x14 / 255, alpha: 1)
    static let darkSurface = NSColor(srgbRed: 0x1A / 255, green: 0x1B / 255, blue: 0x1D / 255, alpha: 1)
    static let darkTintedSurface = NSColor(srgbRed: 0x1F / 255, green: 0x20 / 255, blue: 0x23 / 255, alpha: 1)
    static let lightFrame = NSColor.white
    static let lightSurface = NSColor.white
    static let darkForeground = NSColor(srgbRed: 0xF3 / 255, green: 0xF5 / 255, blue: 0xFB / 255, alpha: 1)
    static let lightForeground = NSColor(srgbRed: 0x11 / 255, green: 0x12 / 255, blue: 0x17 / 255, alpha: 1)

    static var hairline: NSColor { NSColor.labelColor.withAlphaComponent(0.15) }

    static func hoverFill(dark: Bool) -> NSColor {
        (dark ? darkForeground : lightForeground).withAlphaComponent(0.10)
    }

    static func selectedFill(dark: Bool) -> NSColor {
        NSColor.white.withAlphaComponent(dark ? 0.16 : 0.90)
    }

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua ? light : dark
        }
    }

    static var frame: NSColor { dynamic(light: lightFrame, dark: darkFrame) }
    static var surface: NSColor { dynamic(light: lightSurface, dark: darkSurface) }

    static func clampSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(sidebarMaxWidth, max(sidebarMinWidth, width))
    }
}
