import AppKit

enum ChromeIcons {
    static func mappedName(_ symbol: String) -> String {
        switch symbol {
        case "sidebar.left": return "sidebar"
        case "folder", "folder.fill": return "folder"
        case "terminal", "rectangle.split.2x1", "rectangle.split.1x2": return "terminal"
        case "plus", "xmark": return "plus"
        case "gearshape", "gear": return "gear"
        case "chevron.left": return "sidebar"
        case "bell", "bell.badge": return "bell"
        default: return symbol
        }
    }

    static func image(_ name: String, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.white.setFill()
            path(for: name, in: rect).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }

    private static func path(for name: String, in rect: NSRect) -> NSBezierPath {
        let inset = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        switch name {
        case "sidebar":
            let path = NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
            path.append(NSBezierPath(rect: NSRect(x: inset.minX, y: inset.minY, width: inset.width * 0.38, height: inset.height)))
            path.windingRule = .evenOdd
            return path
        case "folder":
            let path = NSBezierPath()
            path.move(to: NSPoint(x: inset.minX, y: inset.minY + inset.height * 0.18))
            path.line(to: NSPoint(x: inset.minX + inset.width * 0.38, y: inset.minY + inset.height * 0.18))
            path.line(to: NSPoint(x: inset.minX + inset.width * 0.48, y: inset.minY + inset.height * 0.38))
            path.line(to: NSPoint(x: inset.maxX, y: inset.minY + inset.height * 0.38))
            path.line(to: NSPoint(x: inset.maxX, y: inset.maxY - inset.height * 0.08))
            path.line(to: NSPoint(x: inset.minX, y: inset.maxY - inset.height * 0.08))
            path.close()
            return path
        case "terminal":
            let path = NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: inset.minX + inset.width * 0.18, y: inset.midY + inset.height * 0.12))
            chevron.line(to: NSPoint(x: inset.minX + inset.width * 0.32, y: inset.midY))
            chevron.line(to: NSPoint(x: inset.minX + inset.width * 0.18, y: inset.midY - inset.height * 0.12))
            chevron.lineWidth = max(1, inset.width * 0.08)
            path.append(chevron)
            return path
        case "plus":
            let t = max(1.5, inset.width * 0.14)
            let path = NSBezierPath(rect: NSRect(x: inset.midX - t / 2, y: inset.minY, width: t, height: inset.height))
            path.append(NSBezierPath(rect: NSRect(x: inset.minX, y: inset.midY - t / 2, width: inset.width, height: t)))
            return path
        case "gear":
            let path = NSBezierPath(ovalIn: inset.insetBy(dx: inset.width * 0.18, dy: inset.height * 0.18))
            path.append(NSBezierPath(ovalIn: inset.insetBy(dx: inset.width * 0.34, dy: inset.height * 0.34)))
            path.windingRule = .evenOdd
            return path
        case "bell":
            let path = NSBezierPath()
            path.move(to: NSPoint(x: inset.minX + inset.width * 0.18, y: inset.minY + inset.height * 0.42))
            path.curve(
                to: NSPoint(x: inset.maxX - inset.width * 0.18, y: inset.minY + inset.height * 0.42),
                controlPoint1: NSPoint(x: inset.minX + inset.width * 0.18, y: inset.maxY - inset.height * 0.08),
                controlPoint2: NSPoint(x: inset.maxX - inset.width * 0.18, y: inset.maxY - inset.height * 0.08)
            )
            path.line(to: NSPoint(x: inset.maxX - inset.width * 0.12, y: inset.minY + inset.height * 0.28))
            path.line(to: NSPoint(x: inset.minX + inset.width * 0.12, y: inset.minY + inset.height * 0.28))
            path.close()
            path.append(NSBezierPath(ovalIn: NSRect(x: inset.midX - inset.width * 0.08, y: inset.minY, width: inset.width * 0.16, height: inset.height * 0.16)))
            return path
        case "split":
            let path = NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
            path.append(NSBezierPath(rect: NSRect(x: inset.midX - 0.5, y: inset.minY, width: 1, height: inset.height)))
            return path
        default:
            return NSBezierPath(roundedRect: inset, xRadius: 2, yRadius: 2)
        }
    }
}
