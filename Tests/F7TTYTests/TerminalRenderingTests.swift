import AppKit
import GhosttyKit
import XCTest

final class TerminalRenderingTests: XCTestCase {
    func testOrdinaryInsertionDoesNotEmitEmptyPreeditResets() async {
        await MainActor.run {
            _ = NSApplication.shared
            let session = GhosttyTerminalSession(host: InactiveTerminalHost())
            let view = GhosttyTerminalView()
            var inserted: [String] = []
            var preedit: [String?] = []
            var handlers = session.makeViewHandlers()
            handlers.insertText = { inserted.append($0) }
            handlers.markedTextChanged = { preedit.append($0) }
            view.handlers = handlers

            let text = ["a", "é", "中文", "🧑🏽‍💻"]
            for value in text {
                view.insertText(value, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            view.unmarkText()
            view.unmarkText()

            XCTAssertEqual(inserted, text)
            XCTAssertTrue(preedit.isEmpty)
            XCTAssertFalse(view.hasMarkedText())
        }
    }

    func testCompositionClearsBeforeCommitAndCanRestartAfterCancellation() async {
        await MainActor.run {
            _ = NSApplication.shared
            let session = GhosttyTerminalSession(host: InactiveTerminalHost())
            let view = GhosttyTerminalView()
            var events: [TerminalInputEvent] = []
            var handlers = session.makeViewHandlers()
            handlers.insertText = { events.append(.insert($0)) }
            handlers.markedTextChanged = { events.append(.preedit($0)) }
            view.handlers = handlers
            let replacement = NSRange(location: NSNotFound, length: 0)

            view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: replacement)
            XCTAssertTrue(view.hasMarkedText())
            XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 3))
            view.setMarkedText(NSAttributedString(string: "日本"), selectedRange: NSRange(location: 2, length: 0), replacementRange: replacement)
            view.insertText(NSAttributedString(string: "日本"), replacementRange: replacement)
            view.unmarkText()
            XCTAssertFalse(view.hasMarkedText())
            XCTAssertEqual(view.markedRange(), replacement)

            view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0), replacementRange: replacement)
            view.unmarkText()
            view.unmarkText()
            view.setMarkedText("e", selectedRange: NSRange(location: 1, length: 0), replacementRange: replacement)
            // Input methods may clear composition by setting an empty marked value.
            view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: replacement)
            view.unmarkText()

            XCTAssertEqual(events, [
                .preedit("にほん"), .preedit("日本"), .preedit(nil), .insert("日本"),
                .preedit("´"), .preedit(nil), .preedit("e"), .preedit(nil),
            ])
            XCTAssertFalse(view.hasMarkedText())
        }
    }

    func testBackingNotificationRepairsLayerScaleAndForwardsSizeWithoutLayout() async {
        await MainActor.run {
            _ = NSApplication.shared
            let session = GhosttyTerminalSession(host: InactiveTerminalHost())
            let view = session.makeView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 321, height: 123),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = view
            defer {
                session.close()
                window.close()
            }
            guard let layer = view.layer else {
                XCTFail("A terminal view must have a backing layer")
                return
            }
            var sizes: [CGSize] = []
            var handlers = session.makeViewHandlers()
            handlers.resize = { sizes.append($0) }
            view.handlers = handlers
            let size = view.bounds.size
            layer.contentsScale = window.backingScaleFactor + 1

            view.viewDidChangeBackingProperties()
            // Even an unchanged scale must forward dimensions; layout may not run.
            view.viewDidChangeBackingProperties()

            XCTAssertEqual(layer.contentsScale, window.backingScaleFactor)
            XCTAssertEqual(sizes, [size, size])
        }
    }
}

private enum TerminalInputEvent: Equatable {
    case preedit(String?)
    case insert(String)
}

@MainActor
private final class InactiveTerminalHost: GhosttyTerminalHostProtocol {
    var app: ghostty_app_t? { nil }
    var config: ghostty_config_t? { nil }
    var configDiagnostics: [GhosttyTerminalConfigDiagnostic] { [] }

    func register(_ session: GhosttyTerminalSession) {}
    func unregister(_ session: GhosttyTerminalSession) {}
    func tick() {}
    func reloadConfig() {}
    func openConfig() {}
    func setColorScheme(_ colorScheme: GhosttyTerminalColorScheme, appearance: NSAppearance?) {}
}
