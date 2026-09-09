import Foundation
import AppKit
import XCTest
@testable import F7TTY

final class WorkspaceModelTests: XCTestCase {
    func testFindBarFitsNarrowPanesWithoutClippingItsButtons() async {
        await MainActor.run {
            _ = NSApplication.shared
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 40))
            let bar = TerminalSearchBar()
            bar.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                bar.topAnchor.constraint(equalTo: root.topAnchor),
                bar.widthAnchor.constraint(equalToConstant: 140)
            ])
            root.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(bar.field.frame.width, 32)
            let controls = bar.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
            XCTAssertEqual(controls.count, 3)
            for button in controls {
                let frame = button.convert(button.bounds, to: bar)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, 140)
                XCTAssertGreaterThanOrEqual(frame.width, 20)
            }
        }
    }

    func testWorkspaceColorPersistsAndLegacyWorkspaceUsesDefault() throws {
        var workspace = Workspace(name: "Home", directory: "/tmp")
        XCTAssertNil(workspace.appColor)
        workspace.appColor = "teal"
        let encoded = try JSONEncoder().encode(workspace)
        XCTAssertEqual(try JSONDecoder().decode(Workspace.self, from: encoded).appColor, "teal")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "appColor")
        XCTAssertNil(try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: legacy)).appColor)
    }

    func testWorkspaceColorControlsSelectAndResetWithoutChangingTerminalSettings() async {
        await MainActor.run {
            _ = NSApplication.shared
            var chosen: String? = "unchanged"
            let view = AppearanceSettingsView(opacity: 1, appearanceMode: "dark", onColorChange: { chosen = $0 }, onChange: { _ in XCTFail("Opacity must not change") }, onAppearanceChange: { _ in XCTFail("Mode must not change") })
            @MainActor func buttons(_ view: NSView) -> [WorkspaceColorButton] {
                if let button = view as? WorkspaceColorButton { return [button] }
                return view.subviews.flatMap(buttons)
            }
            let colors = buttons(view)
            XCTAssertEqual(colors.count, 7)
            colors.first { $0.color == .teal }?.performClick(nil)
            XCTAssertEqual(chosen, "teal")
            XCTAssertEqual(colors.filter { $0.state == .on }.map(\.color), [.teal])
            colors.first { $0.color == .standard }?.performClick(nil)
            XCTAssertNil(chosen)
            XCTAssertEqual(colors.filter { $0.state == .on }.map(\.color), [.standard])
        }
    }

    func testActivityHistoryIncludesOlderEventsAndDisablesClosedTerminals() async {
        await MainActor.run {
            _ = NSApplication.shared
            let controller = TerminalActivityViewController()
            let liveID = UUID()
            controller.isTerminalAvailable = { $0 == liveID }
            controller.events = (0..<9).map { index in
                TerminalActivity(terminalID: index == 8 ? liveID : UUID(), title: "Event \(index)", detail: "Detail")
            }
            controller.loadViewIfNeeded()
            @MainActor func buttons(_ view: NSView) -> [NSButton] {
                if let button = view as? NSButton { return [button] }
                return view.subviews.flatMap(buttons)
            }
            XCTAssertEqual(buttons(controller.view).filter { $0.title.hasPrefix("Event") }.count, 6)
            controller.showAll()
            let events = buttons(controller.view).filter { $0.title.hasPrefix("Event") }
            XCTAssertEqual(events.count, 9)
            XCTAssertEqual(events.filter(\.isEnabled).map(\.title), ["Event 8"])
            XCTAssertTrue(events[0].toolTip?.contains("closed") == true)
        }
    }

    func testActivityPanelEscapeAndEmptyToPopulatedTransitions() async {
        await MainActor.run {
            _ = NSApplication.shared
            let controller = TerminalActivityViewController()
            var dismissed = false
            controller.onDismiss = { dismissed = true }
            controller.loadViewIfNeeded()
            XCTAssertEqual(controller.preferredContentSize.height, 90)
            controller.events = [TerminalActivity.event(.ringBell, terminalID: UUID())!]
            XCTAssertEqual(controller.preferredContentSize.height, 120)
            (controller.view as? ActivityContentView)?.cancelOperation(nil)
            XCTAssertTrue(dismissed)
            controller.events = []
            XCTAssertEqual(controller.preferredContentSize.height, 90)
        }
    }

    func testActivityOnlyRecordsExplicitTerminalEventsAndBoundsText() {
        let id = UUID()
        XCTAssertNil(TerminalActivity.event(.render, terminalID: id))
        XCTAssertNil(TerminalActivity.event(.setTitle("working"), terminalID: id))
        XCTAssertEqual(TerminalActivity.event(.ringBell, terminalID: id)?.terminalID, id)
        let event = TerminalActivity.event(.desktopNotification(title: String(repeating: "a", count: 500), body: String(repeating: "b", count: 1000)), terminalID: id)
        XCTAssertEqual(event?.title.count, 160)
        XCTAssertEqual(event?.detail.count, 320)
    }

    func testSidebarReorderPreservesTerminalsSelectionAndDirectories() throws {
        let a = WorkspaceSession(name: "A", directory: "/tmp/a")
        let b = WorkspaceSession(name: "B", directory: "/tmp/b")
        let c = WorkspaceSession(name: "C", directory: "/tmp/c")
        let first = Workspace(name: "First", directory: "/tmp", sessions: [a, b])
        let second = Workspace(name: "Second", directory: "/", sessions: [c])
        var state = WorkspaceState(workspaces: [first, second], selectedWorkspaceID: first.id, selectedSessionID: a.id)
        XCTAssertTrue(state.reorderSidebar(source: a.id, target: b.id, after: true))
        XCTAssertEqual(state.workspaces[0].sessions, [b, a])
        XCTAssertTrue(state.reorderSidebar(source: a.id, target: c.id, after: false))
        XCTAssertEqual(state.workspaces[1].sessions, [a, c])
        XCTAssertEqual(state.selectedWorkspaceID, second.id)
        XCTAssertEqual(state.selectedSessionID, a.id)
        XCTAssertTrue(state.reorderSidebar(source: second.id, target: first.id, after: false))
        XCTAssertEqual(state.workspaces.map(\.id), [second.id, first.id])
        try state.validate()
        let before = state
        XCTAssertFalse(state.reorderSidebar(source: a.id, target: a.id, after: false))
        XCTAssertFalse(state.reorderSidebar(source: first.id, target: a.id, after: false))
        XCTAssertFalse(state.reorderSidebar(source: UUID(), target: a.id, after: false))
        XCTAssertEqual(state, before)
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state)), state)
    }

    func testSessionMoveToWorkspacePreservesStateAndRejectsInvalidTargets() throws {
        let session = WorkspaceSession(name: "Running", directory: "/tmp/original")
        let other = WorkspaceSession(name: "Other", directory: "/tmp/other")
        let source = Workspace(name: "Source", directory: "/tmp", sessions: [session, other])
        let destination = Workspace(name: "Empty", directory: "/", sessions: [])
        var state = WorkspaceState(workspaces: [source, destination], selectedWorkspaceID: source.id, selectedSessionID: session.id)
        XCTAssertTrue(state.reorderSidebar(source: session.id, target: destination.id, after: false))
        XCTAssertEqual(state.workspaces[0].sessions, [other])
        XCTAssertEqual(state.workspaces[1].sessions, [session])
        XCTAssertEqual(state.selectedWorkspaceID, destination.id)
        XCTAssertEqual(state.selectedSessionID, session.id)
        XCTAssertTrue(state.reorderSidebar(source: other.id, target: destination.id, after: false))
        XCTAssertTrue(state.workspaces[0].sessions.isEmpty)
        XCTAssertEqual(state.workspaces[1].sessions, [session, other])
        XCTAssertEqual(state.selectedSessionID, session.id)
        let before = state
        XCTAssertFalse(state.reorderSidebar(source: session.id, target: destination.id, after: false))
        XCTAssertFalse(state.reorderSidebar(source: session.id, target: UUID(), after: false))
        XCTAssertEqual(state, before)
        try state.validate()
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state)), state)
    }

    func testAppearancePanelsResolveLayerColorsOnModeChanges() async {
        await MainActor.run {
            _ = NSApplication.shared
            let view = AppearanceSettingsView(opacity: 1, appearanceMode: "dark", onChange: { _ in }, onAppearanceChange: { _ in })
            view.appearance = NSAppearance(named: .darkAqua)
            view.updateColors()
            let dark = NSColor(cgColor: view.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            view.appearance = NSAppearance(named: .aqua)
            view.updateColors()
            let light = NSColor(cgColor: view.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            XCTAssertLessThan(dark.redComponent, 0.2)
            XCTAssertGreaterThan(light.redComponent, 0.95)
            view.fillOpacity = 0.4
            XCTAssertEqual(NSColor(cgColor: view.layer!.backgroundColor!)!.alphaComponent, 0.4, accuracy: 0.001)
        }
    }

    func testAutomaticTitlesRespectRenamesAndPersistTheirMode() throws {
        var session = WorkspaceSession(name: "Terminal 1", directory: "/tmp/project")
        XCTAssertEqual(session.displayTitle(liveTitle: "Agent working"), "Terminal 1")
        session.usesAutomaticTitle = true
        XCTAssertEqual(session.displayTitle(liveTitle: nil), "project")
        XCTAssertEqual(session.displayTitle(liveTitle: "  Agent working  "), "Agent working")
        let restored = try JSONDecoder().decode(WorkspaceSession.self, from: JSONEncoder().encode(session))
        XCTAssertTrue(restored.usesAutomaticTitle)
        XCTAssertEqual(restored.displayTitle(liveTitle: nil), "project")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        legacy.removeValue(forKey: "usesAutomaticTitle")
        let old = try JSONDecoder().decode(WorkspaceSession.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(old.usesAutomaticTitle)
        XCTAssertEqual(old.displayTitle(liveTitle: "New shell title"), "Terminal 1")
    }

    func testWorkspaceChromeHasNoDividerButPaneSplitsRemainResizable() async {
        await MainActor.run {
            XCTAssertEqual(WorkspaceSplitView().dividerThickness, 0)
            XCTAssertEqual(PaneSplitView().dividerThickness, 8)
        }
    }

    func testUnpeelTokensClampSidebarAndKeepOpaqueFrameDarkerThanSurface() {
        XCTAssertEqual(Theme.clampSidebarWidth(180), 220)
        XCTAssertEqual(Theme.clampSidebarWidth(600), 520)
        XCTAssertEqual(Theme.clampSidebarWidth(300), 300)
        XCTAssertEqual(Theme.windowMinSize, NSSize(width: 800, height: 600))
        XCTAssertLessThan(Theme.darkFrame.redComponent, Theme.darkSurface.redComponent)
        XCTAssertEqual(Theme.contentCornerRadius, 10)
        XCTAssertEqual(Theme.surfaceInset, 8)
    }

    func testNewSessionNamesDoNotCollideAfterRemovalOrRename() {
        var workspace = Workspace(name: "Home", directory: "/tmp", sessions: [
            WorkspaceSession(name: "Terminal 1", directory: "/tmp"),
            WorkspaceSession(name: "Terminal 3", directory: "/tmp"),
            WorkspaceSession(name: "Build", directory: "/tmp")
        ])
        XCTAssertEqual(workspace.nextSessionName, "Terminal 2")
        workspace.sessions.append(WorkspaceSession(name: workspace.nextSessionName, directory: "/tmp"))
        XCTAssertEqual(workspace.nextSessionName, "Terminal 4")
        workspace.sessions.removeAll()
        XCTAssertEqual(workspace.nextSessionName, "Terminal 1")
    }

    func testPaneDropRejectsSelfAndMalformedSource() async {
        await MainActor.run {
            let id = UUID()
            let other = UUID()
            let pane = PaneContainerView(terminalID: id)
            XCTAssertNil(pane.acceptedSourceID(id.uuidString))
            XCTAssertNil(pane.acceptedSourceID("not-a-pane"))
            XCTAssertEqual(pane.acceptedSourceID(other.uuidString), other)
        }
    }

    func testPaletteNavigationSkipsSectionHeadings() async {
        await MainActor.run {
            _ = NSApplication.shared
            let palette = CommandPaletteView(entries: [
                PaletteEntry(title: "Terminal", detail: "Home", shortcut: "", group: .sessions) {},
                PaletteEntry(title: "Home", detail: "Project", shortcut: "", group: .projects) {},
                PaletteEntry(title: "Settings", detail: "Command", shortcut: "") {}
            ])
            XCTAssertEqual(palette.numberOfRows(in: palette.table), 6)
            XCTAssertEqual(palette.table.selectedRow, 1)
            XCTAssertFalse(palette.tableView(palette.table, shouldSelectRow: 2))
            let editor = NSTextView()
            _ = palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
            XCTAssertEqual(palette.table.selectedRow, 3)
            var selected = ""
            palette.onChoose = { selected = $0.title }
            _ = palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            XCTAssertEqual(selected, "Home")
            _ = palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:)))
            XCTAssertEqual(palette.table.selectedRow, 1)
        }
    }

    func testFindFocusOwnershipDoesNotIncludeAnotherFieldEditor() async {
        await MainActor.run {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let bar = TerminalSearchBar(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
            let other = NSTextField(frame: NSRect(x: 0, y: 50, width: 300, height: 30))
            window.contentView?.addSubview(bar)
            window.contentView?.addSubview(other)
            XCTAssertFalse(bar.ownsKeyboardFocus)
            window.makeFirstResponder(bar.field)
            XCTAssertTrue(bar.ownsKeyboardFocus)
            window.makeFirstResponder(other)
            XCTAssertFalse(bar.ownsKeyboardFocus)
            window.close()
        }
    }

    func testPaletteFiltersAndRoutesSelectionWithoutExecutingOnSearch() async {
        await MainActor.run {
            _ = NSApplication.shared
            var executed = 0
            let entries = [
                PaletteEntry(title: "Terminal", detail: "Project One", shortcut: "") { executed += 1 },
                PaletteEntry(title: "Settings", detail: "Command", shortcut: "⌘,") { executed += 10 }
            ]
            XCTAssertEqual(PaletteEntry.matching(entries, query: "project TERMINAL").map(\.title), ["Terminal"])
            let palette = CommandPaletteView(entries: entries)
            palette.onChoose = { $0.action() }
            var dismissed = false
            palette.onDismiss = { dismissed = true }
            palette.field.stringValue = "settings"
            palette.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            XCTAssertEqual(executed, 0)
            XCTAssertEqual(palette.filtered.map(\.title), ["Settings"])
            let editor = NSTextView()
            XCTAssertTrue(palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertEqual(executed, 10)
            palette.field.stringValue = "no match"
            palette.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            _ = palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
            XCTAssertEqual(executed, 10)
            _ = palette.control(palette.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
            XCTAssertTrue(dismissed)
        }
    }

    func testTerminalSearchRoutesQueryReturnAndEscape() async {
        await MainActor.run {
            let bar = TerminalSearchBar()
            var query = ""
            var next = false
            var closed = false
            bar.onQuery = { query = $0 }
            bar.onNavigate = { next = $0 }
            bar.onClose = { closed = true }
            bar.field.stringValue = "needle"
            bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            XCTAssertEqual(query, "needle")
            let editor = NSTextView()
            XCTAssertTrue(bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertTrue(next)
            XCTAssertTrue(bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            XCTAssertTrue(closed)
            XCTAssertFalse(bar.control(bar.field, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
            XCTAssertEqual(bar.field.focusRingType, .none)
        }
    }

    func testDirectionalFocusUsesGeometryWithoutWrapping() {
        let frames: [UUID: CGRect] = [
            first: CGRect(x: 0, y: 0, width: 400, height: 600),
            second: CGRect(x: 408, y: 308, width: 300, height: 292),
            third: CGRect(x: 408, y: 0, width: 300, height: 300)
        ]
        XCTAssertEqual(PaneNavigation.neighbor(of: second, direction: .down, frames: frames), third)
        XCTAssertEqual(PaneNavigation.neighbor(of: third, direction: .up, frames: frames), second)
        XCTAssertEqual(PaneNavigation.neighbor(of: second, direction: .left, frames: frames), first)
        XCTAssertNil(PaneNavigation.neighbor(of: first, direction: .left, frames: frames))
        XCTAssertNil(PaneNavigation.neighbor(of: second, direction: .right, frames: frames))
    }

    func testSessionHoverCloseReceivesItsOwnClick() async {
        await MainActor.run {
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            let row = SidebarRowButton(frame: NSRect(x: 8, y: 100, width: 284, height: 28))
            row.sessionRow = true
            root.addSubview(row)
            let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            row.mouseEntered(with: event)
            XCTAssertTrue(row.hitTest(NSPoint(x: 20, y: 110)) is ActionButton)
            XCTAssertEqual(row.accessibilityChildren()?.count, 1)
            row.mouseExited(with: event)
            XCTAssertTrue(row.hitTest(NSPoint(x: 20, y: 110)) === row)
            XCTAssertNil(row.hitTest(NSPoint(x: 20, y: 80)))
        }
    }

    func testFolderHoverAddReceivesClickWithoutCollapsingFolder() async {
        await MainActor.run {
            _ = NSApplication.shared
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
            let row = SidebarRowButton(frame: NSRect(x: 8, y: 100, width: 284, height: 28))
            var added = false
            row.onAdd = { added = true }
            root.addSubview(row)
            let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
            row.mouseEntered(with: event)
            guard let button = row.hitTest(NSPoint(x: 276, y: 110)) as? ActionButton else {
                return XCTFail("Expected the folder add button")
            }
            button.performClick(nil)
            XCTAssertTrue(added)
            XCTAssertEqual(row.accessibilityChildren()?.count, 1)
            row.mouseExited(with: event)
            XCTAssertTrue(row.hitTest(NSPoint(x: 276, y: 110)) === row)
        }
    }

    func testPaneHeaderDoesNotInterceptClicksOutsideItsBounds() async {
        await MainActor.run {
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
            let header = PaneHeaderView(terminalID: UUID())
            header.frame = NSRect(x: 20, y: 200, width: 300, height: 28)
            root.addSubview(header)
            XCTAssertNil(header.hitTest(NSPoint(x: 40, y: 100)))
            XCTAssertTrue(header.hitTest(NSPoint(x: 40, y: 210)) === header)
            let button = ActionButton("Split", symbol: "plus", action: {})
            button.frame = NSRect(x: 260, y: 0, width: 28, height: 28)
            header.addSubview(button)
            XCTAssertTrue(header.hitTest(NSPoint(x: 290, y: 210)) === button)
            XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.height, 28)
            XCTAssertFalse(button.acceptsFirstResponder)
            XCTAssertTrue(button.acceptsFirstMouse(for: nil))
        }
    }

    func testPersistenceSavesReplacesAndRetainsInvalidData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let store = WorkspacePersistence(fileURL: url)
        guard case .missing = store.load() else { return XCTFail("Expected no state") }
        var state = WorkspaceState.fresh(directory: "/tmp")
        try store.save(state)
        state.workspaces[0].name = "Renamed"
        try store.save(state)
        guard case .loaded(let loaded) = store.load() else { return XCTFail("Expected saved state") }
        XCTAssertEqual(state, loaded)
        let invalid = Data("not a layout".utf8)
        try invalid.write(to: url)
        guard case .invalid = store.load() else { return XCTFail("Expected invalid state") }
        XCTAssertThrowsError(try store.save(state))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }

    func testZoomIsNotPersistedAndSplittingRevealsNewPane() throws {
        var session = WorkspaceSession(name: "Shell", directory: "/tmp", terminalID: first)
        session.toggleZoom(for: first)
        let restored = try JSONDecoder().decode(WorkspaceSession.self, from: JSONEncoder().encode(session))
        XCTAssertNil(restored.zoomedTerminalID)
        XCTAssertEqual(restored.tree, session.tree)
        session.split(terminalID: first, direction: .right, newTerminalID: second)
        XCTAssertNil(session.zoomedTerminalID)
    }

    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let fourth = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    func testSplitsUseTheRequestedDirectionAndPreserveTerminalIDs() throws {
        var session = WorkspaceSession(name: "Main", directory: "/tmp", terminalID: first)

        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        XCTAssertEqual(session.terminalIDs, [first, second])
        XCTAssertEqual(session.tree, .split(axis: .horizontal, ratio: 0.5, first: .terminal(first), second: .terminal(second)))

        XCTAssertTrue(session.split(terminalID: second, direction: .down, newTerminalID: third))
        XCTAssertEqual(Set(session.terminalIDs), Set([first, second, third]))
        XCTAssertEqual(session.tree.leafCount, 3)
        XCTAssertTrue(session.setRatio(at: [], to: 0.65))
        if case .split(_, let ratio, _, _) = session.tree {
            XCTAssertEqual(ratio, 0.65, accuracy: 0.0001)
        } else {
            XCTFail("Expected a split root")
        }

        var directional = WorkspaceSession(name: "Directions", directory: "/tmp", terminalID: first)
        XCTAssertTrue(directional.split(terminalID: first, direction: .left, newTerminalID: fourth))
        XCTAssertTrue(directional.split(terminalID: fourth, direction: .up, newTerminalID: third))
        XCTAssertEqual(Set(directional.terminalIDs), Set([first, third, fourth]))
    }

    func testNestedRemoveCollapsesTheParent() throws {
        var session = WorkspaceSession(name: "Main", directory: "/tmp", terminalID: first)
        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        XCTAssertTrue(session.split(terminalID: second, direction: .down, newTerminalID: third))

        XCTAssertTrue(session.remove(terminalID: third))
        XCTAssertEqual(session.terminalIDs, [first, second])
        XCTAssertEqual(session.tree.leafCount, 2)
        XCTAssertFalse(session.remove(terminalID: UUID()))
    }

    func testMoveEdgeNestsAndCenterSwapsWithoutRecreatingIDs() throws {
        var session = WorkspaceSession(name: "Main", directory: "/tmp", terminalID: first)
        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        XCTAssertTrue(session.split(terminalID: second, direction: .down, newTerminalID: third))
        let beforeMoveIDs = Set(session.terminalIDs)

        XCTAssertTrue(session.move(terminalID: first, to: third, zone: .left))
        XCTAssertEqual(Set(session.terminalIDs), beforeMoveIDs)
        XCTAssertEqual(session.tree.leafCount, 3)

        XCTAssertTrue(session.move(terminalID: first, to: second, zone: .center))
        XCTAssertEqual(Set(session.terminalIDs), beforeMoveIDs)
        XCTAssertTrue(session.contains(terminalID: first))
        XCTAssertTrue(session.contains(terminalID: second))
    }

    func testSamePaneAndInvalidDropDoNotMutate() throws {
        var session = WorkspaceSession(name: "Main", directory: "/tmp", terminalID: first)
        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        let original = session

        XCTAssertFalse(session.move(terminalID: first, to: first, zone: .center))
        XCTAssertEqual(session, original)
        XCTAssertFalse(session.move(terminalID: first, to: UUID(), zone: .right))
        XCTAssertEqual(session, original)
        XCTAssertFalse(session.move(terminalID: first, to: second, zone: .invalid))
        XCTAssertEqual(session, original)
        XCTAssertFalse(session.split(terminalID: first, direction: .left, newTerminalID: second))
        XCTAssertEqual(session, original)
    }

    func testZoomOnlyChangesPresentationStateAndLeavesTreeUnchanged() throws {
        var session = WorkspaceSession(name: "Main", directory: "/tmp", terminalID: first)
        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        let originalTree = session.tree

        XCTAssertTrue(session.toggleZoom(for: second))
        XCTAssertEqual(session.tree, originalTree)
        XCTAssertEqual(session.zoomedTerminalID, second)
        XCTAssertTrue(session.toggleZoom(for: second))
        XCTAssertNil(session.zoomedTerminalID)
        XCTAssertEqual(session.tree, originalTree)
    }

    func testCodableRoundTripAndInvalidTreeValidation() throws {
        var workspace = Workspace(name: "Project", directory: "/tmp/project")
        var session = WorkspaceSession(name: "Shell", directory: "/tmp/project", terminalID: first)
        XCTAssertTrue(session.split(terminalID: first, direction: .right, newTerminalID: second))
        workspace.sessions = [session]
        let state = WorkspaceState(workspaces: [workspace], selectedWorkspaceID: workspace.id, selectedSessionID: session.id)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        XCTAssertEqual(decoded, state)

        var duplicate = session
        duplicate.id = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        duplicate.tree = .split(axis: .horizontal, ratio: 0.5, first: .terminal(first), second: .terminal(first))
        var invalid = workspace
        invalid.sessions = [session, duplicate]
        let duplicateState = WorkspaceState(workspaces: [invalid])
        XCTAssertThrowsError(try duplicateState.validate())

        var invalidRatio = session
        invalidRatio.tree = .split(axis: .horizontal, ratio: 1, first: .terminal(first), second: .terminal(second))
        XCTAssertThrowsError(try invalidRatio.validate())

        var invalidReference = session
        invalidReference.zoomedTerminalID = fourth
        XCTAssertThrowsError(try invalidReference.validate())
        XCTAssertThrowsError(try invalidReference.tree.validate(referencing: Set([first])))
    }
}
