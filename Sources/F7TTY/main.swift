import AppKit
import GhosttyKit
import ProcessOwnership

let charcoal = NSColor(white: 0.105, alpha: 1)

enum Assets {
    static let bundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("F7TTY_F7TTY.bundle"),
           let bundled = Bundle(url: url) { return bundled }
        return Bundle.module
    }()
}

@MainActor
final class ActionButton: NSButton {
    var handler: () -> Void = {}
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    var controlDimension: CGFloat = 28 { didSet { invalidateIntrinsicContentSize() } }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: imagePosition == .imageOnly ? controlDimension : max(80, super.intrinsicContentSize.width + 16), height: controlDimension)
    }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && (hovered || isHighlighted) {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.14 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
        super.draw(dirtyRect)
    }

    convenience init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.handler = action
        target = self
        self.action = #selector(run)
        isBordered = false
        bezelStyle = .texturedRounded
        font = .systemFont(ofSize: 12)
        focusRingType = .none
        setContentCompressionResistancePriority(.required, for: .horizontal)
        contentTintColor = .secondaryLabelColor
        toolTip = title
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            imagePosition = .imageOnly
        }
        setAccessibilityLabel(title)
    }

    @objc private func run() {
        handler()
    }
}

@MainActor
final class SidebarDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The workspace chrome is continuous; only terminal cards draw a separating border.
@MainActor
final class WorkspaceSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 0 }
    override func drawDivider(in rect: NSRect) {}
}

@MainActor
final class SidebarRowButton: NSButton, NSDraggingSource {
    nonisolated static let reorderType = NSPasteboard.PasteboardType("pt.funnysoft.f7tty.sidebar-row")
    var onReorder: ((UUID, UUID, Bool) -> Void)? {
        didSet { registerForDraggedTypes([Self.reorderType]) }
    }
    private var dragOrigin: NSPoint?
    private var startedDrag = false
    private var dropAfter: Bool?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard onReorder != nil else { super.mouseDown(with: event); return }
        dragOrigin = event.locationInWindow
        startedDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard onReorder != nil, let itemID, let dragOrigin, !startedDrag,
              hypot(event.locationInWindow.x - dragOrigin.x, event.locationInWindow.y - dragOrigin.y) > 5 else { return }
        startedDrag = true
        let payload = NSPasteboardItem()
        payload.setString("\(sessionRow ? "session" : "workspace"):\(itemID.uuidString)", forType: Self.reorderType)
        let item = NSDraggingItem(pasteboardWriter: payload)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        (title as NSString).draw(at: NSPoint(x: 32, y: 7), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
        image.unlockFocus()
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        guard onReorder != nil else { super.mouseUp(with: event); return }
        if !startedDrag && bounds.contains(convert(event.locationInWindow, from: nil)) { performClick(nil) }
        dragOrigin = nil
        startedDrag = false
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragOrigin = nil; startedDrag = false; dropAfter = nil; needsDisplay = true
    }
    private func reorderSource(_ sender: NSDraggingInfo) -> UUID? {
        guard sender.draggingSource is SidebarRowButton,
              let value = sender.draggingPasteboard.string(forType: Self.reorderType) else { return nil }
        let parts = value.split(separator: ":")
        guard parts.count == 2, parts[0] == (sessionRow ? "session" : "workspace"),
              let id = UUID(uuidString: String(parts[1])), id != itemID else { return nil }
        return id
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard onReorder != nil, reorderSource(sender) != nil else { dropAfter = nil; needsDisplay = true; return [] }
        let point = convert(sender.draggingLocation, from: nil)
        dropAfter = isFlipped ? point.y > bounds.midY : point.y < bounds.midY
        needsDisplay = true
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropAfter = nil; needsDisplay = true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropAfter = nil; needsDisplay = true }
        guard let source = reorderSource(sender), let itemID, let dropAfter, let onReorder else { return false }
        onReorder(source, itemID, dropAfter)
        return true
    }
    var itemID: UUID?
    var contextMenuProvider: (() -> NSMenu?)?
    var sessionRow = false
    var selectedRow = false
    var shortcutLabel = ""
    var onRemove: (() -> Void)?
    var onAdd: (() -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var hovered = false
    private lazy var removeButton = ActionButton("Remove session", symbol: "xmark") { [weak self] in self?.onRemove?() }
    private lazy var addButton = ActionButton("New session", symbol: "plus") { [weak self] in self?.onAdd?() }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; updateHover() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHover() }

    private func updateHover() {
        if sessionRow {
            if removeButton.superview == nil { addSubview(removeButton) }
            removeButton.frame = NSRect(x: 2, y: 0, width: 28, height: bounds.height)
            removeButton.isHidden = !hovered
        } else if onAdd != nil {
            if addButton.superview == nil { addSubview(addButton) }
            addButton.frame = NSRect(x: max(0, bounds.width - 30), y: 0, width: 28, height: bounds.height)
            addButton.isHidden = !hovered
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let local = convert(point, from: superview)
        if sessionRow && !removeButton.isHidden && removeButton.frame.contains(local) { return removeButton }
        if !sessionRow && onAdd != nil && hovered && addButton.frame.contains(local) { return addButton }
        return hit
    }

    override func accessibilityChildren() -> [Any]? {
        guard hovered else { return [] }
        return sessionRow ? [removeButton] : onAdd != nil ? [addButton] : []
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { title }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let action else { return false }
        return NSApp.sendAction(action, to: target, from: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        if let dropAfter {
            NSColor.secondaryLabelColor.setFill()
            let bottom = dropAfter != isFlipped
            NSRect(x: 8, y: bottom ? 0 : bounds.height - 2, width: max(0, bounds.width - 16), height: 2).fill()
        }
        if selectedRow || hovered {
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
            NSColor.white.withAlphaComponent(selectedRow ? 0.21 : 0.045).setFill()
            shape.fill()
            if selectedRow {
                NSColor.white.withAlphaComponent(0.23).setStroke()
                shape.lineWidth = 0.75
                shape.stroke()
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textRect = NSRect(x: 32, y: (bounds.height - 17) / 2, width: max(0, bounds.width - (shortcutLabel.isEmpty ? 58 : 92)), height: 17)
        (title as NSString).draw(in: textRect, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: contentTintColor ?? NSColor.labelColor, .paragraphStyle: paragraph])
        let iconRect = NSRect(x: sessionRow ? bounds.width - 22 : 8, y: (bounds.height - 14) / 2, width: 14, height: 14)
        image?.withSymbolConfiguration(.init(paletteColors: [NSColor(white: 0.65, alpha: 1)]))?
            .draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if !shortcutLabel.isEmpty {
            (shortcutLabel as NSString).draw(in: NSRect(x: bounds.width - 58, y: (bounds.height - 15) / 2, width: 32, height: 15), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

@MainActor
final class PaneHeaderView: NSView, NSDraggingSource {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    let terminalID: UUID
    var onDragStarted: ((UUID) -> Void)?
    var onClick: (() -> Void)?
    private var dragStartPoint: NSPoint?
    private var didStartDrag = false

    init(terminalID: UUID) {
        self.terminalID = terminalID
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is ActionButton { return hit }
            view = current.superview
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, let dragStartPoint else { return }
        let current = event.locationInWindow
        guard hypot(current.x - dragStartPoint.x, current.y - dragStartPoint.y) > 5 else { return }
        didStartDrag = true

        let item = NSPasteboardItem()
        item.setString(terminalID.uuidString, forType: .f7ttyPane)
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
        onDragStarted?(terminalID)
    }

    override func mouseUp(with event: NSEvent) {
        if !didStartDrag { onClick?() }
        dragStartPoint = nil
        didStartDrag = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // AppKit owns mouse-up during a drag, including cancellation with Escape.
        dragStartPoint = nil
        didStartDrag = false
    }

    private func dragImage() -> NSImage {
        let image = NSImage(size: NSSize(width: max(80, bounds.width), height: max(22, bounds.height)))
        image.lockFocus()
        NSColor(white: 0.16, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: image.size), xRadius: 5, yRadius: 5).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
final class PaneContainerView: NSView {
    nonisolated static let panePasteboardType = NSPasteboard.PasteboardType("com.funnysoft.f7tty.pane")

    let terminalID: UUID
    var dropHandler: ((UUID, UUID, PaneDropZone) -> Bool)?
    private let dropPreview = NSView()
    private var currentDropZone: PaneDropZone?

    init(terminalID: UUID) {
        self.terminalID = terminalID
        super.init(frame: .zero)
        registerForDraggedTypes([Self.panePasteboardType])
        dropPreview.wantsLayer = true
        dropPreview.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
        dropPreview.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        dropPreview.layer?.borderWidth = 1
        dropPreview.layer?.cornerRadius = 6
        dropPreview.isHidden = true
        addSubview(dropPreview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggingTerminalID(from: sender) != nil else {
            clearDropPreview()
            return []
        }
        updateDropPreview(for: sender)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggingTerminalID(from: sender) != nil else {
            clearDropPreview()
            return []
        }
        updateDropPreview(for: sender)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropPreview()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        draggingTerminalID(from: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { clearDropPreview() }
        guard let draggedID = draggingTerminalID(from: sender), let currentDropZone else { return false }
        return dropHandler?(draggedID, terminalID, currentDropZone) == true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearDropPreview()
    }

    private func draggingTerminalID(from sender: NSDraggingInfo) -> UUID? {
        guard let value = sender.draggingPasteboard.string(forType: Self.panePasteboardType) else { return nil }
        return acceptedSourceID(value)
    }

    func acceptedSourceID(_ value: String) -> UUID? {
        guard let id = UUID(uuidString: value), id != terminalID else { return nil }
        return id
    }

    private func updateDropPreview(for sender: NSDraggingInfo) {
        addSubview(dropPreview, positioned: .above, relativeTo: nil)
        let point = convert(sender.draggingLocation, from: nil)
        let zone = dropZone(at: point)
        currentDropZone = zone

        let inset: CGFloat = 7
        let previewFrame: NSRect
        switch zone {
        case .left:
            previewFrame = NSRect(x: inset, y: inset, width: max(1, bounds.width * 0.28), height: max(1, bounds.height - inset * 2))
        case .right:
            previewFrame = NSRect(x: bounds.width * 0.72, y: inset, width: max(1, bounds.width * 0.28 - inset), height: max(1, bounds.height - inset * 2))
        case .top:
            previewFrame = NSRect(x: inset, y: bounds.height * 0.72, width: max(1, bounds.width - inset * 2), height: max(1, bounds.height * 0.28 - inset))
        case .bottom:
            previewFrame = NSRect(x: inset, y: inset, width: max(1, bounds.width - inset * 2), height: max(1, bounds.height * 0.28))
        case .center:
            previewFrame = bounds.insetBy(dx: bounds.width * 0.2, dy: bounds.height * 0.2)
        case .invalid:
            previewFrame = .zero
        }
        dropPreview.frame = previewFrame
        dropPreview.isHidden = zone == .invalid
    }

    private func dropZone(at point: NSPoint) -> PaneDropZone {
        guard bounds.width > 1, bounds.height > 1, bounds.contains(point) else { return .invalid }
        let horizontalEdge = max(42, bounds.width * 0.25)
        let verticalEdge = max(42, bounds.height * 0.25)
        if point.x < horizontalEdge { return .left }
        if point.x > bounds.width - horizontalEdge { return .right }
        if point.y > bounds.height - verticalEdge { return .top }
        if point.y < verticalEdge { return .bottom }
        return .center
    }

    private func clearDropPreview() {
        currentDropZone = nil
        dropPreview.isHidden = true
    }
}

@MainActor
final class Pane {
    let terminalID: UUID
    let session: GhosttyTerminalSession
    let terminal: GhosttyTerminalView
    let container: PaneContainerView
    let title = NSTextField(labelWithString: "Terminal")
    let header: PaneHeaderView
    private(set) var zoomButton: ActionButton!
    private var searchBar: TerminalSearchBar?

    init(
        host: GhosttyTerminalHost,
        terminalID: UUID,
        directory: String,
        test: Bool,
        onFocus: @escaping () -> Void,
        onSplit: @escaping (SplitDirection) -> Void,
        onZoom: @escaping () -> Void,
        onEqualize: @escaping () -> Void,
        onNewSession: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onMenu: @escaping () -> Void,
        onMove: @escaping (UUID, UUID, PaneDropZone) -> Bool
    ) {
        self.terminalID = terminalID
        session = host.makeSession(configuration: .init(
            command: PerformanceDiagnostics.benchmark ? Self.benchmarkCommand : (test ? "/bin/zsh -f" : nil),
            workingDirectory: directory,
            environment: ["F7TTY": test ? "SMOKE" : "1"],
            fontSize: 13,
            colorScheme: .dark
        ))
        terminal = session.makeView()
        container = PaneContainerView(terminalID: terminalID)
        header = PaneHeaderView(terminalID: terminalID)

        container.wantsLayer = true
        // Terminal configuration is independently dark; keep its chrome legible.
        container.appearance = NSAppearance(named: .darkAqua)
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.cornerRadius = PerformanceDiagnostics.experiment("F7TTY_SQUARE_PANES") ? 0 : 9
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor(white: 0.2, alpha: 1).cgColor
        container.layer?.masksToBounds = !PerformanceDiagnostics.experiment("F7TTY_SQUARE_PANES")

        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.maximumNumberOfLines = 1
        title.stringValue = (directory as NSString).abbreviatingWithTildeInPath
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let icon = NSImageView(image: NSImage(systemSymbolName: "terminal", accessibilityDescription: "Terminal")!)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let splitRight = ActionButton("Split right", symbol: "rectangle.split.2x1") { onSplit(.right) }
        let splitDown = ActionButton("Split below", symbol: "rectangle.split.1x2") { onSplit(.down) }
        let zoom = ActionButton("Maximize pane", symbol: "arrow.up.left.and.arrow.down.right") { onZoom() }
        zoomButton = zoom
        let more = ActionButton("Pane actions", symbol: "ellipsis") { onMenu() }
        let headerStack = NSStackView(views: [icon, title, splitRight, splitDown, zoom, more])
        headerStack.orientation = .horizontal
        headerStack.distribution = .fill
        headerStack.alignment = .centerY
        headerStack.spacing = 2

        [header, terminal].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerStack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 11),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            header.heightAnchor.constraint(equalToConstant: 28),
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerStack.topAnchor.constraint(equalTo: header.topAnchor),
            headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            terminal.topAnchor.constraint(equalTo: header.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.dropHandler = { draggedID, targetID, zone in
            onMove(draggedID, targetID, zone)
        }
        header.onDragStarted = { _ in onFocus() }
        header.onClick = onFocus

        if var handlers = terminal.handlers {
            handlers.primaryInteraction = onFocus
            terminal.handlers = handlers
        }
        session.actionHandler = { [weak self] action in
            guard let self else { return }
            self.onActivity?(action)
            switch action {
            case .startSearch(let query): self.showSearch(query: query)
            case .endSearch: self.hideSearch()
            case .searchTotal, .searchSelected:
                self.searchBar?.update(total: self.session.state.searchTotal, selected: self.session.state.searchSelected)
            default: break
            }
            if case .setTitle(let value) = action,
               let value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Shell titles commonly prefix the path with user@host. Keep
                // the complete value in the tooltip without crowding controls.
                let parts = value.components(separatedBy: ":")
                let displayTitle = parts.count == 2 && parts[0].contains("@") ? parts[1] : value
                if self.title.toolTip != value { self.title.toolTip = value }
                if self.title.stringValue != displayTitle {
                    self.title.stringValue = displayTitle
                    self.onTitleChanged?()
                }
            }
        }
        session.requestHandler = { request in
            switch request {
            case .newSplit(let direction):
                switch direction {
                case .left: onSplit(.left)
                case .right: onSplit(.right)
                case .up: onSplit(.up)
                case .down: onSplit(.down)
                }
            case .toggleSplitZoom:
                onZoom()
            case .equalizeSplits:
                onEqualize()
            case .newTab:
                onNewSession()
            case .closeTab:
                onClose()
            case .closeWindow:
                NSApp.terminate(nil)
            default:
                break
            }
        }
    }

    var onTitleChanged: (() -> Void)?
    var onActivity: ((GhosttyTerminalAction) -> Void)?

    private static var benchmarkCommand: String {
        let script = Assets.bundle.url(forResource: "render-workload", withExtension: "py", subdirectory: "Resources")!.path
        let quotedPath = "'" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let scenario = ProcessInfo.processInfo.environment["F7TTY_BENCHMARK_SCENARIO"] ?? "animate"
        return "/usr/bin/python3 \(quotedPath) \(scenario == "idle" ? "idle" : scenario == "titles" ? "titles" : "animate")"
    }

    func visibility(_ visible: Bool) {
        let changed = container.isHidden == visible
        container.isHidden = !visible
        session.setOccluded(!visible)
        if visible && changed {
            terminal.requestRender()
        }
    }

    func showSearch(query: String? = nil) {
        if searchBar == nil {
            let bar = TerminalSearchBar()
            searchBar = bar
            bar.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(bar, positioned: .above, relativeTo: nil)
            let width = bar.widthAnchor.constraint(equalToConstant: 340)
            width.priority = .defaultHigh
            NSLayoutConstraint.activate([
                bar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
                bar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
                bar.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 10),
                width
            ])
            bar.onQuery = { [weak self] query in
                PerformanceDiagnostics.record("searchRequests")
                _ = self?.session.perform(action: "search:\(query)")
            }
            bar.onNavigate = { [weak self] next in self?.navigateSearch(next: next) }
            bar.onClose = { [weak self] in
                _ = self?.session.perform(action: "end_search")
                self?.hideSearch()
            }
        }
        if let query { searchBar?.field.stringValue = query }
        if !container.isHiddenOrHasHiddenAncestor, let field = searchBar?.field {
            container.window?.makeFirstResponder(field)
        }
    }

    func navigateSearch(next: Bool) {
        searchBar?.flushPendingQuery()
        _ = session.perform(action: next ? "navigate_search:next" : "navigate_search:previous")
    }

    private func hideSearch() {
        guard let searchBar else { return }
        searchBar.cancelPendingQuery()
        let restoreFocus = searchBar.ownsKeyboardFocus && !container.isHiddenOrHasHiddenAncestor
        searchBar.removeFromSuperview()
        self.searchBar = nil
        if restoreFocus { requestFocus() }
    }

    func updateZoomState(_ zoomed: Bool) {
        let label = zoomed ? "Restore pane layout" : "Maximize pane"
        zoomButton.toolTip = label
        zoomButton.setAccessibilityLabel(label)
        zoomButton.image = NSImage(systemSymbolName: zoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", accessibilityDescription: label)
    }

    func requestFocus() {
        guard !container.isHiddenOrHasHiddenAncestor, container.window != nil else { return }
        terminal.requestFocus()
    }

    func close() {
        session.close()
    }
}

@MainActor
final class PaneSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 8 }
    override func drawDivider(in rect: NSRect) {
        NSColor(white: 0.075, alpha: 1).setFill()
        rect.fill()
    }
}

@MainActor
final class PaneTreeView: NSView, NSSplitViewDelegate {
    private let path: [Int]
    private let ratio: Double
    private let onRatioChange: ([Int], Double) -> Void
    private var splitView: NSSplitView?
    private var didApplyInitialRatio = false
    private var suppressResizeFeedback = false
    private var lastReportedRatio: Double

    init(
        node: PaneTree,
        panes: [UUID: Pane],
        path: [Int],
        onRatioChange: @escaping ([Int], Double) -> Void
    ) {
        self.path = path
        self.onRatioChange = onRatioChange
        switch node {
        case .terminal:
            ratio = 0.5
        case .split(_, let value, _, _):
            ratio = value
        }
        lastReportedRatio = ratio
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        switch node {
        case .terminal(let terminalID):
            if let pane = panes[terminalID] {
                pane.container.translatesAutoresizingMaskIntoConstraints = false
                addSubview(pane.container)
                NSLayoutConstraint.activate([
                    pane.container.leadingAnchor.constraint(equalTo: leadingAnchor),
                    pane.container.trailingAnchor.constraint(equalTo: trailingAnchor),
                    pane.container.topAnchor.constraint(equalTo: topAnchor),
                    pane.container.bottomAnchor.constraint(equalTo: bottomAnchor)
                ])
            }
        case .split(let axis, _, let first, let second):
            let paneSplit = PaneSplitView()
            paneSplit.isVertical = axis == .horizontal
            paneSplit.dividerStyle = .thin
            paneSplit.delegate = self
            paneSplit.translatesAutoresizingMaskIntoConstraints = false
            splitView = paneSplit
            addSubview(paneSplit)
            NSLayoutConstraint.activate([
                paneSplit.leadingAnchor.constraint(equalTo: leadingAnchor),
                paneSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
                paneSplit.topAnchor.constraint(equalTo: topAnchor),
                paneSplit.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            let firstView = PaneTreeView(node: first, panes: panes, path: path + [0], onRatioChange: onRatioChange)
            let secondView = PaneTreeView(node: second, panes: panes, path: path + [1], onRatioChange: onRatioChange)
            firstView.translatesAutoresizingMaskIntoConstraints = true
            secondView.translatesAutoresizingMaskIntoConstraints = true
            paneSplit.addArrangedSubview(firstView)
            paneSplit.addArrangedSubview(secondView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        guard let splitView else { return }
        applyRatio(to: splitView)
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        applyRatio(to: splitView)
    }

    private func applyRatio(to splitView: NSSplitView) {
        guard splitView.subviews.count == 2 else { return }
        let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let available = length - splitView.dividerThickness
        guard available > 0 else { return }
        suppressResizeFeedback = true
        let position = CGFloat(lastReportedRatio) * available
        if splitView.isVertical {
            splitView.subviews[0].frame = NSRect(x: 0, y: 0, width: position, height: splitView.bounds.height)
            splitView.subviews[1].frame = NSRect(x: position + splitView.dividerThickness, y: 0,
                width: available - position, height: splitView.bounds.height)
        } else {
            splitView.subviews[0].frame = NSRect(x: 0, y: 0, width: splitView.bounds.width, height: position)
            splitView.subviews[1].frame = NSRect(x: 0, y: position + splitView.dividerThickness,
                width: splitView.bounds.width, height: available - position)
        }
        didApplyInitialRatio = true
        suppressResizeFeedback = false
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let available = max(0, length - splitView.dividerThickness)
        guard available > 240 else { return available / 2 }
        let minimum: CGFloat = 120
        return min(max(proposedPosition, minimum), available - minimum)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard didApplyInitialRatio, !suppressResizeFeedback, NSEvent.pressedMouseButtons & 1 != 0, let splitView else { return }
        let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
        let available = length - splitView.dividerThickness
        guard available > 0 else { return }
        let position = splitView.subviews.first?.frame.width ?? 0
        let measured = splitView.isVertical
            ? position / available
            : (splitView.subviews.first?.frame.height ?? 0) / available
        guard measured.isFinite else { return }
        let normalized = min(0.99, max(0.01, Double(measured)))
        guard abs(normalized - lastReportedRatio) > 0.001 else { return }
        lastReportedRatio = normalized
        onRatioChange(path, normalized)
    }
}

@MainActor
final class F7TTYAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var window: NSWindow!
    var host: GhosttyTerminalHost!
    var model = WorkspaceState(workspaces: [])
    private var saveScheduler: WorkspaceSaveScheduler?
    var panes: [UUID: Pane] = [:]
    var paneTreeView: PaneTreeView?
    var focusedTerminalID: UUID?
    var sidebarVisible = true
    var quitting = false
    let test = CommandLine.arguments.contains("--smoke-test")
    let preview = CommandLine.arguments.contains("--ui-preview") || CommandLine.arguments.contains("--empty-preview") || CommandLine.arguments.contains("--benchmark")
    var smokeFailed = false
    private var rootView = AppearancePanel()
    private var backgroundBlur: NSVisualEffectView?
    private let body = WorkspaceSplitView()
    private let sidebar = AppearancePanel()
    private let sidebarRows = NSStackView()
    private var automaticTitleRows: [UUID: (row: SidebarRowButton, resolveTitle: (String?) -> String)] = [:]
    private let canvas = AppearancePanel()
    private let emptyState = AppearancePanel()
    private var emptyLeadingConstraint: NSLayoutConstraint?
    private var emptyTopConstraint: NSLayoutConstraint?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var persistenceErrorShown = false
    private var invalidSavedStateError: Error?
    private var settingsView: AppearanceSettingsView?
    private var commandPalette: CommandPaletteView?
    private var settingsTopConstraint: NSLayoutConstraint?
    private var paneLeadingConstraint: NSLayoutConstraint?
    private var paneTopConstraint: NSLayoutConstraint?
    private var visibleTerminalIDs = Set<UUID>()
    private var collapsedWorkspaceIDs = Set<UUID>()
    private var emptyWorkspaceIDs = Set<UUID>()
    private var backgroundOpacity: Double = 1
    private var appearanceMode = "dark"
    private var activity: [TerminalActivity] = []
    private var activityPopover: NSPopover?
    private var activityController: TerminalActivityViewController?
    private var activityButton: ActionButton?
    private var benchmarkFinishSignal: DispatchSourceSignal?
    private var benchmarkInitialCounts: [String: Int] = [:]
    private var benchmarkStartTime: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--export-icon"), CommandLine.arguments.count > index + 1 {
            let bitmap = NSBitmapImageRep(data: Brand.image().tiffRepresentation!)!
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        appearanceMode = test || preview ? "dark" : UserDefaults.standard.string(forKey: "appearanceMode") ?? "dark"
        applyAppearanceMode()

        do {
            host = try GhosttyTerminalHost(
                loadDefaultTheme: false,
                configFile: Assets.bundle.url(forResource: "terminal", withExtension: "conf", subdirectory: "Resources")!.path
            )
            guard host.configDiagnostics.isEmpty else {
                throw NSError(
                    domain: "F7TTY.Config",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: host.configDiagnostics.map(\.message).joined(separator: "\n")]
                )
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
            return
        }

        // Keep the Ghostty surface color scheme in sync with the native app
        // chrome when Settings changes System, Light, or Dark.
        applyAppearanceMode()

        if !test && !preview {
            loadSavedModel()
        }
        installMenus()
        buildWindow()

        if test || preview {
            makeSmokeModel()
        }
        normalizeSelection()
        refreshSidebar()
        renderSelectedSession()

        window.center()
        window.makeKeyAndOrderFront(nil)
        body.setPosition(300, ofDividerAt: 0)
        NSApp.applicationIconImage = Brand.image()
        NSApp.activate(ignoringOtherApps: true)

        if let invalidSavedStateError {
            DispatchQueue.main.async { [weak self] in
                self?.presentPersistenceError(invalidSavedStateError)
            }
        }
        if test {
            runSmokeTest()
        } else if PerformanceDiagnostics.benchmark {
            runBenchmark()
        }
    }

    private func loadSavedModel() {
        guard let fileURL = WorkspacePersistence.applicationSupportURL() else { return }
        let store = WorkspacePersistence(fileURL: fileURL)
        switch store.load() {
        case .missing:
            model = WorkspaceState(workspaces: [])
        case .loaded(let saved):
            model = saved
        case .invalid(let error):
            model = WorkspaceState(workspaces: [])
            invalidSavedStateError = error
        }
        saveScheduler = WorkspaceSaveScheduler(persistence: store) { [weak self] error in
            self?.presentPersistenceError(error)
        }
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "F7TTY"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.075, alpha: 1)
        window.minSize = NSSize(width: 650, height: 400)
        window.delegate = self
        window.isReleasedWhenClosed = false

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(white: 0.075, alpha: 1).cgColor
        body.isVertical = true
        body.dividerStyle = .thin
        body.translatesAutoresizingMaskIntoConstraints = false
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        body.addArrangedSubview(sidebar)
        body.addArrangedSubview(canvas)
        rootView.addSubview(body)
        let sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: 300)
        sidebarWidthConstraint = sidebarWidth
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            body.topAnchor.constraint(equalTo: rootView.topAnchor),
            body.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            sidebarWidth,
            canvas.widthAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

        configureSidebar()
        configureCanvas()
        backgroundOpacity = test || preview ? 1 : UserDefaults.standard.object(forKey: "backgroundOpacity") as? Double ?? 1
        applyBackgroundOpacity(backgroundOpacity)
        let toggle = ActionButton("Toggle sidebar", symbol: "sidebar.left") { [weak self] in self?.toggleSidebar() }
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.wantsLayer = true
        toggle.layer?.backgroundColor = NSColor.clear.cgColor
        toggle.layer?.cornerRadius = 5
        rootView.addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 86),
            toggle.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 4),
            toggle.widthAnchor.constraint(equalToConstant: 29),
            toggle.heightAnchor.constraint(equalToConstant: 25)
        ])
        window.contentView = rootView
        let bell = ActionButton("Recent activity", symbol: "bell") { [weak self] in self?.showActivity() }
        bell.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(bell)
        activityButton = bell
        NSLayoutConstraint.activate([
            bell.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 2),
            bell.centerYAnchor.constraint(equalTo: toggle.centerYAnchor),
            bell.widthAnchor.constraint(equalToConstant: 28),
            bell.heightAnchor.constraint(equalToConstant: 25)
        ])
    }

    private func configureSidebar() {
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor(red: 0.064, green: 0.068, blue: 0.072, alpha: 1).cgColor
        let heading = NSTextField(labelWithString: "")
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = NSColor(white: 0.48, alpha: 1)
        heading.translatesAutoresizingMaskIntoConstraints = false

        sidebarRows.orientation = .vertical
        sidebarRows.alignment = .leading
        sidebarRows.spacing = 2
        sidebarRows.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let document = SidebarDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        sidebar.addSubview(heading)
        sidebar.addSubview(scroll)
        document.addSubview(sidebarRows)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 47),
            heading.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -15),
            heading.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 32),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 48),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -56),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            sidebarRows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 8),
            sidebarRows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            sidebarRows.topAnchor.constraint(equalTo: document.topAnchor),
            sidebarRows.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 4
        footer.translatesAutoresizingMaskIntoConstraints = false
        let add = ActionButton("New session or workspace", symbol: "plus") { [weak self] in self?.showNewMenu() }
        let settings = ActionButton("Settings", symbol: "gearshape") { [weak self] in self?.showSettings() }
        footer.addArrangedSubview(add)
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(settings)
        sidebar.addSubview(footer)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            footer.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func configureCanvas() {
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor(red: 0.064, green: 0.068, blue: 0.072, alpha: 1).cgColor
        emptyState.darkFill = NSColor(white: 0.105, alpha: 1)
        emptyState.lightFill = NSColor(white: 0.97, alpha: 1)
        emptyState.updateColors()
        emptyState.layer?.cornerRadius = 9
        emptyState.layer?.borderWidth = 1
        emptyState.layer?.borderColor = NSColor(white: 0.23, alpha: 1).cgColor
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let mark = NSImageView(image: Brand.image())
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.translatesAutoresizingMaskIntoConstraints = false
        let message = NSTextField(labelWithString: "No session selected")
        message.font = .systemFont(ofSize: 14, weight: .medium)
        message.textColor = .secondaryLabelColor
        let guidance = NSTextField(wrappingLabelWithString: "Pick a session in the sidebar, or hit + on a project")
        guidance.font = .systemFont(ofSize: 12)
        guidance.textColor = .tertiaryLabelColor
        guidance.alignment = .center
        let version = NSTextField(labelWithString: "v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3")")
        version.font = .systemFont(ofSize: 11, weight: .medium)
        version.textColor = .tertiaryLabelColor
        [mark, message, guidance, version].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(20, after: guidance)
        emptyState.addSubview(stack)
        canvas.addSubview(emptyState)
        emptyLeadingConstraint = emptyState.leadingAnchor.constraint(equalTo: canvas.leadingAnchor)
        emptyTopConstraint = emptyState.topAnchor.constraint(equalTo: canvas.topAnchor, constant: 8)
        NSLayoutConstraint.activate([
            emptyLeadingConstraint!,
            emptyTopConstraint!,
            emptyState.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8),
            emptyState.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -8),
            mark.widthAnchor.constraint(equalToConstant: 64),
            mark.heightAnchor.constraint(equalToConstant: 64),
            stack.leadingAnchor.constraint(equalTo: emptyState.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: emptyState.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor),
            guidance.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func makeSmokeModel() {
        let workspace = Workspace(name: "Smoke", directory: FileManager.default.homeDirectoryForCurrentUser.path)
        model = WorkspaceState(workspaces: [workspace], selectedWorkspaceID: workspace.id)
        guard !CommandLine.arguments.contains("--empty-preview") else { return }
        _ = addSession(to: workspace.id, name: PerformanceDiagnostics.benchmark ? nil : "Terminal", select: true, persist: false)
    }

    private func refreshSidebar() {
        PerformanceDiagnostics.record("sidebarRebuilds")
        let emptyIDs = Set(model.workspaces.filter { $0.sessions.isEmpty }.map(\.id))
        // Collapse newly empty folders, but preserve an explicit expansion until they change again.
        collapsedWorkspaceIDs.formUnion(emptyIDs.subtracting(emptyWorkspaceIDs))
        collapsedWorkspaceIDs.formIntersection(model.workspaces.map(\.id))
        emptyWorkspaceIDs = emptyIDs
        let color = selectedWorkspace?.appColor.flatMap(WorkspaceColor.init(rawValue:)) ?? .standard
        for panel in [rootView, sidebar, canvas] {
            panel.darkFill = color.darkFill
            panel.lightFill = color.lightFill
            panel.updateColors()
        }
        if window.isOpaque { window.backgroundColor = rootView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)) ?? .windowBackgroundColor }
        automaticTitleRows.removeAll(keepingCapacity: true)
        for view in sidebarRows.arrangedSubviews {
            sidebarRows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if settingsView != nil {
            let back = ActionButton("Back", symbol: "chevron.left") { [weak self] in self?.closeSettings() }
            back.imagePosition = .imageLeading
            back.title = "Back"
            sidebarRows.addArrangedSubview(back)
            let appearance = SidebarRowButton(frame: .zero)
            appearance.title = "Appearance"
            appearance.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
            appearance.selectedRow = true
            appearance.isBordered = false
            appearance.translatesAutoresizingMaskIntoConstraints = false
            sidebarRows.addArrangedSubview(appearance)
            appearance.widthAnchor.constraint(equalTo: sidebarRows.widthAnchor).isActive = true
            appearance.heightAnchor.constraint(equalToConstant: 29).isActive = true
            return
        }

        let numberedSessions = Array(model.workspaces.flatMap(\.sessions).prefix(9)).map(\.id)
        for workspace in model.workspaces {
            let workspaceRow = SidebarRowButton(frame: .zero)
            workspaceRow.title = workspace.name
            workspaceRow.toolTip = collapsedWorkspaceIDs.contains(workspace.id) ? "Expand folder" : "Collapse folder"
            workspaceRow.image = NSImage(systemSymbolName: collapsedWorkspaceIDs.contains(workspace.id) ? "folder.fill" : "folder", accessibilityDescription: "Workspace")
            workspaceRow.imagePosition = .imageLeading
            workspaceRow.alignment = .left
            workspaceRow.font = .systemFont(ofSize: 13)
            workspaceRow.contentTintColor = .secondaryLabelColor
            workspaceRow.isBordered = false
            workspaceRow.target = self
            workspaceRow.action = #selector(selectWorkspaceFromRow(_:))
            workspaceRow.itemID = workspace.id
            workspaceRow.onReorder = { [weak self] source, target, after in self?.reorderSidebar(source: source, target: target, after: after) }
            workspaceRow.onAdd = { [weak self] in
                _ = self?.addSession(to: workspace.id, name: nil, select: true, persist: true)
            }
            workspaceRow.contextMenuProvider = { [weak self] in self?.workspaceMenu(for: workspace.id) }
            workspaceRow.translatesAutoresizingMaskIntoConstraints = false
            workspaceRow.heightAnchor.constraint(equalToConstant: 28).isActive = true
            sidebarRows.addArrangedSubview(workspaceRow)
            workspaceRow.widthAnchor.constraint(equalTo: sidebarRows.widthAnchor).isActive = true

            if collapsedWorkspaceIDs.contains(workspace.id) { continue }
            if workspace.sessions.isEmpty {
                let empty = SidebarRowButton(frame: .zero)
                empty.title = "No sessions yet."
                empty.font = .systemFont(ofSize: 12)
                empty.contentTintColor = .secondaryLabelColor
                empty.isBordered = false
                empty.target = self
                empty.action = #selector(newSessionFromEmptyFolder(_:))
                empty.itemID = workspace.id
                empty.toolTip = "New session"
                empty.translatesAutoresizingMaskIntoConstraints = false
                sidebarRows.addArrangedSubview(empty)
                empty.heightAnchor.constraint(equalToConstant: 24).isActive = true
                empty.widthAnchor.constraint(equalTo: sidebarRows.widthAnchor).isActive = true
            }
            for session in workspace.sessions {
                let row = SidebarRowButton(frame: .zero)
                let firstID = session.terminalIDs.first
                if session.usesAutomaticTitle, let firstID {
                    automaticTitleRows[firstID] = (row, session.displayTitle(liveTitle:))
                }
                row.title = session.displayTitle(liveTitle: firstID.flatMap { panes[$0]?.title.stringValue })
                row.sessionRow = true
                if let index = numberedSessions.firstIndex(of: session.id) { row.shortcutLabel = "⌘\(index + 1)" }
                row.selectedRow = session.id == model.selectedSessionID
                row.onRemove = { [weak self] in
                    guard let self else { return }
                    self.removeSession(self.contextItem("Remove session", action: #selector(self.removeSession(_:)), id: session.id))
                }
                row.image = NSImage(systemSymbolName: session.tree.leafCount > 1 ? "rectangle.split.2x1" : "terminal", accessibilityDescription: "Session")
                row.imagePosition = .imageLeading
                row.alignment = .left
                row.font = .systemFont(ofSize: 13)
                row.contentTintColor = session.id == model.selectedSessionID ? .labelColor : .secondaryLabelColor
                row.isBordered = false
                row.wantsLayer = true
                row.layer?.cornerRadius = 7
                row.layer?.backgroundColor = NSColor.clear.cgColor
                row.target = self
                row.action = #selector(selectSessionFromRow(_:))
                row.itemID = session.id
                row.onReorder = { [weak self] source, target, after in self?.reorderSidebar(source: source, target: target, after: after) }
                row.toolTip = session.directory
                row.contextMenuProvider = { [weak self] in self?.sessionMenu(for: session.id) }
                row.translatesAutoresizingMaskIntoConstraints = false
                row.heightAnchor.constraint(equalToConstant: 29).isActive = true
                sidebarRows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: sidebarRows.widthAnchor).isActive = true
            }
        }
    }

    private func reorderSidebar(source: UUID, target: UUID, after: Bool) {
        guard model.reorderSidebar(source: source, target: target, after: after) else { return }
        // No surface rebuild, reparent, focus change, shell restart or working-directory change.
        refreshSidebar()
        saveModel()
    }

    private func renderSelectedSession() {
        PerformanceDiagnostics.record("layoutRebuilds")
        // Reparent and lay out in one transaction. Do not animate live Metal
        // surfaces through intermediate sizes or expose an empty frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            canvas.layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
        for id in visibleTerminalIDs {
            guard let pane = panes[id] else { continue }
            pane.visibility(false)
            pane.container.removeFromSuperview()
        }
        visibleTerminalIDs.removeAll(keepingCapacity: true)
        paneLeadingConstraint = nil
        paneTopConstraint = nil
        paneTreeView?.removeFromSuperview()
        paneTreeView = nil

        if settingsView != nil {
            emptyState.isHidden = true
            return
        }

        guard let session = selectedSession else {
            emptyState.isHidden = false
            return
        }
        emptyState.isHidden = true
        ensureRuntime(for: session)
        for id in session.terminalIDs { panes[id]?.updateZoomState(session.zoomedTerminalID == id) }

        if let zoomedID = session.zoomedTerminalID, let pane = panes[zoomedID] {
            addPaneContentToCanvas(pane.container)
            pane.visibility(true)
            visibleTerminalIDs.insert(zoomedID)
        } else {
            let tree = PaneTreeView(node: session.tree, panes: panes, path: []) { [weak self] path, ratio in
                self?.updateRatio(for: session.id, path: path, ratio: ratio)
            }
            paneTreeView = tree
            addPaneContentToCanvas(tree)
            for id in session.terminalIDs {
                panes[id]?.visibility(true)
                visibleTerminalIDs.insert(id)
            }
        }

        if let focusedTerminalID, session.contains(terminalID: focusedTerminalID) {
            panes[focusedTerminalID]?.requestFocus()
        } else {
            focusedTerminalID = session.terminalIDs.first
            if let focusedTerminalID {
                panes[focusedTerminalID]?.requestFocus()
            }
        }
    }

    private func addPaneContentToCanvas(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(view)
        paneLeadingConstraint = view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: sidebarVisible ? 0 : 8)
        paneTopConstraint = view.topAnchor.constraint(equalTo: canvas.topAnchor, constant: sidebarVisible ? 8 : 38)
        NSLayoutConstraint.activate([
            paneLeadingConstraint!,
            view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8),
            paneTopConstraint!,
            view.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -8)
        ])
    }

    private func ensureRuntime(for session: WorkspaceSession) {
        for terminalID in session.terminalIDs where panes[terminalID] == nil {
            panes[terminalID] = Pane(
                host: host,
                terminalID: terminalID,
                directory: session.directory,
                test: test,
                onFocus: { [weak self] in self?.focusPane(terminalID) },
                onSplit: { [weak self] direction in self?.splitPane(terminalID: terminalID, direction: direction) },
                onZoom: { [weak self] in self?.toggleZoom(for: terminalID) },
                onEqualize: { [weak self] in self?.equalizeSplits() },
                onNewSession: { [weak self] in self?.newSession() },
                onClose: { [weak self] in self?.closePane(terminalID) },
                onMenu: { [weak self] in self?.showPaneMenu(for: terminalID) },
                onMove: { [weak self] draggedID, targetID, zone in
                    self?.movePane(draggedID: draggedID, targetID: targetID, zone: zone) == true
                }
            )
            panes[terminalID]?.onTitleChanged = { [weak self] in
                guard let self, self.settingsView == nil,
                      let automaticTitle = self.automaticTitleRows[terminalID],
                      let rawTitle = self.panes[terminalID]?.title.stringValue else { return }
                let row = automaticTitle.row
                let title = automaticTitle.resolveTitle(rawTitle)
                guard row.title != title else { return }
                row.title = title
                PerformanceDiagnostics.record("sidebarTitleUpdates")
            }
            panes[terminalID]?.session.applyColorScheme(colorScheme(for: appearanceMode), appearance: window?.effectiveAppearance)
            panes[terminalID]?.onActivity = { [weak self] action in
                guard let self, let event = TerminalActivity.event(action, terminalID: terminalID) else { return }
                self.activity.insert(event, at: 0)
                self.activity = Array(self.activity.prefix(50))
                if self.activityPopover?.isShown == true { self.activityController?.events = self.activity }
                self.activityButton?.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Recent activity")
            }
            panes[terminalID]?.session.closeHandler = { [weak self] processAlive in
                guard let pane = self?.panes[terminalID] else { return }
                if processAlive {
                    pane.title.stringValue = "Close requested"
                } else {
                    pane.title.stringValue = "Process exited"
                }
            }
        }
    }

    private func focusPane(_ terminalID: UUID) {
        guard let session = selectedSession, session.contains(terminalID: terminalID) else { return }
        focusedTerminalID = terminalID
        panes[terminalID]?.requestFocus()
    }

    private func splitPane(terminalID: UUID, direction: SplitDirection) {
        guard let session = selectedSession, session.contains(terminalID: terminalID) else { return }
        let newID = UUID()
        guard mutateSession(session.id, { session in
            session.split(terminalID: terminalID, direction: direction, newTerminalID: newID)
        }) else {
            NSSound.beep()
            return
        }
        focusedTerminalID = newID
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    private func toggleZoom(for terminalID: UUID) {
        guard let session = selectedSession else { return }
        guard mutateSession(session.id, { $0.toggleZoom(for: terminalID) }) else { return }
        focusedTerminalID = terminalID
        renderSelectedSession()
    }

    private func closePane(_ terminalID: UUID) {
        guard let session = selectedSession, session.contains(terminalID: terminalID) else { return }
        if session.tree.leafCount == 1 {
            closeFocusedSession()
            return
        }
        guard test || confirmDestructiveAction(title: "Close terminal pane?",
            message: "Commands in this pane will be stopped.", action: "Close pane") else { return }
        guard mutateSession(session.id, { $0.remove(terminalID: terminalID) }) else { return }
        let pane = panes.removeValue(forKey: terminalID)
        pane?.container.removeFromSuperview()
        pane?.close()
        focusedTerminalID = selectedSession?.terminalIDs.first
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    private func movePane(draggedID: UUID, targetID: UUID, zone: PaneDropZone) -> Bool {
        guard let session = selectedSession else { return false }
        guard mutateSession(session.id, { $0.move(terminalID: draggedID, to: targetID, zone: zone) }) else {
            NSSound.beep()
            return false
        }
        focusedTerminalID = draggedID
        refreshSidebar()
        renderSelectedSession()
        saveModel()
        return true
    }

    private func updateRatio(for sessionID: UUID, path: [Int], ratio: Double) {
        guard mutateSession(sessionID, { $0.setRatio(at: path, to: ratio) }) else { return }
        saveModel(delay: 0.2)
    }

    private func newSession() {
        guard let workspaceID = model.selectedWorkspaceID else {
            newWorkspace()
            return
        }
        _ = addSession(to: workspaceID, name: nil, select: true, persist: true)
    }

    private func showNewMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let sessionItem = NSMenuItem(title: "New session", action: #selector(newSessionCommand), keyEquivalent: "")
        sessionItem.target = self
        sessionItem.isEnabled = selectedWorkspace != nil
        menu.addItem(sessionItem)
        let workspaceItem = NSMenuItem(title: "New workspace", action: #selector(newWorkspaceCommand), keyEquivalent: "")
        workspaceItem.target = self
        menu.addItem(workspaceItem)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @discardableResult
    private func addSession(to workspaceID: UUID, name: String?, select: Bool, persist: Bool) -> Bool {
        guard let index = model.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return false }
        let workspace = model.workspaces[index]
        var session = WorkspaceSession(
            name: name ?? workspace.nextSessionName,
            directory: workspace.directory
        )
        session.usesAutomaticTitle = name == nil
        guard model.workspaces[index].append(session: session) else { return false }
        if select {
            if settingsView != nil { closeSettings() }
            collapsedWorkspaceIDs.remove(workspaceID)
            model.selectedWorkspaceID = workspaceID
            model.selectedSessionID = session.id
            focusedTerminalID = session.terminalIDs.first
        }
        refreshSidebar()
        renderSelectedSession()
        if persist { saveModel() }
        return true
    }

    private func newWorkspace() {
        let panel = NSOpenPanel()
        panel.title = "Choose a workspace folder"
        panel.message = "F7TTY will start new sessions in this folder."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let workspace = Workspace(name: name, directory: url.path)
        model.workspaces.append(workspace)
        model.selectedWorkspaceID = workspace.id
        _ = addSession(to: workspace.id, name: nil, select: true, persist: true)
    }

    private func selectWorkspace(_ id: UUID) {
        guard id != model.selectedWorkspaceID else { return }
        guard let workspace = model.workspaces.first(where: { $0.id == id }) else { return }
        model.selectedWorkspaceID = id
        model.selectedSessionID = workspace.sessions.first?.id
        focusedTerminalID = selectedSession?.terminalIDs.first
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    private func selectSession(_ id: UUID) {
        guard id != model.selectedSessionID else {
            if let focusedTerminalID { panes[focusedTerminalID]?.requestFocus() }
            return
        }
        guard let workspace = model.workspaces.first(where: { $0.sessions.contains(where: { $0.id == id }) }) else { return }
        model.selectedWorkspaceID = workspace.id
        model.selectedSessionID = id
        focusedTerminalID = workspace.sessions.first(where: { $0.id == id })?.terminalIDs.first
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    @objc private func selectWorkspaceFromRow(_ sender: SidebarRowButton) {
        guard let id = sender.itemID else { return }
        toggleWorkspaceExpansion(id)
    }

    private func toggleWorkspaceExpansion(_ id: UUID) {
        guard model.workspaces.contains(where: { $0.id == id }) else { return }
        if !collapsedWorkspaceIDs.insert(id).inserted { collapsedWorkspaceIDs.remove(id) }
        refreshSidebar()
    }

    @objc private func collapseAllFolders() {
        collapsedWorkspaceIDs = Set(model.workspaces.map(\.id))
        refreshSidebar()
    }

    @objc private func selectSessionFromRow(_ sender: SidebarRowButton) {
        guard let id = sender.itemID else { return }
        selectSession(id)
    }

    private func workspaceMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(contextItem("Rename workspace", action: #selector(renameWorkspace(_:)), id: id))
        menu.addItem(contextItem("New session", action: #selector(newSessionFromMenu(_:)), id: id))
        menu.addItem(.separator())
        menu.addItem(contextItem("Remove workspace", action: #selector(removeWorkspace(_:)), id: id))
        return menu
    }

    private func sessionMenu(for id: UUID) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(contextItem("Rename session", action: #selector(renameSession(_:)), id: id))
        menu.addItem(contextItem("New session", action: #selector(newSessionFromMenu(_:)), id: id))
        menu.addItem(.separator())
        menu.addItem(contextItem("Close session", action: #selector(removeSession(_:)), id: id))
        return menu
    }

    private func contextItem(_ title: String, action: Selector, id: UUID) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id.uuidString
        return item
    }

    @objc private func newSessionFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let id = UUID(uuidString: value) else { return }
        if model.workspaces.contains(where: { $0.id == id }) {
            model.selectedWorkspaceID = id
            _ = addSession(to: id, name: nil, select: true, persist: true)
        } else if let workspaceID = model.workspaces.first(where: { $0.sessions.contains(where: { $0.id == id }) })?.id {
            model.selectedWorkspaceID = workspaceID
            _ = addSession(to: workspaceID, name: nil, select: true, persist: true)
        }
    }

    @objc private func renameWorkspace(_ sender: NSMenuItem) {
        guard let id = contextID(from: sender), let index = model.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename workspace"
        let field = NSTextField(string: model.workspaces[index].name)
        field.frame.size = NSSize(width: 270, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Rename")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { NSSound.beep(); return }
        model.workspaces[index].name = value
        refreshSidebar()
        saveModel()
    }

    @objc private func renameSession(_ sender: NSMenuItem) {
        guard let id = contextID(from: sender), let location = sessionLocation(id) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename session"
        let field = NSTextField(string: model.workspaces[location.workspace].sessions[location.session].name)
        field.frame.size = NSSize(width: 270, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Rename")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { NSSound.beep(); return }
        model.workspaces[location.workspace].sessions[location.session].name = value
        model.workspaces[location.workspace].sessions[location.session].usesAutomaticTitle = false
        refreshSidebar()
        saveModel()
    }

    @objc private func removeWorkspace(_ sender: NSMenuItem) {
        guard let id = contextID(from: sender), let index = model.workspaces.firstIndex(where: { $0.id == id }) else { return }
        let workspace = model.workspaces[index]
        guard confirmDestructiveAction(
            title: "Remove workspace?",
            message: "This closes all terminals in \(workspace.name).",
            action: "Remove workspace"
        ) else { return }
        closeRuntime(for: workspace)
        model.workspaces.remove(at: index)
        normalizeSelection()
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    @objc private func removeSession(_ sender: NSMenuItem) {
        guard let id = contextID(from: sender), let location = sessionLocation(id) else { return }
        let session = model.workspaces[location.workspace].sessions[location.session]
        guard confirmDestructiveAction(
            title: "Close session?",
            message: "This closes the terminal panes in \(session.name).",
            action: "Close session"
        ) else { return }
        closeRuntime(for: session)
        model.workspaces[location.workspace].sessions.remove(at: location.session)
        normalizeSelection()
        refreshSidebar()
        renderSelectedSession()
        saveModel()
    }

    private func confirmDestructiveAction(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action).keyEquivalent = "\r"
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func closeRuntime(for workspace: Workspace) {
        for session in workspace.sessions {
            closeRuntime(for: session)
        }
    }

    private func closeRuntime(for session: WorkspaceSession) {
        for terminalID in session.terminalIDs {
            panes.removeValue(forKey: terminalID)?.close()
        }
        if let focusedTerminalID, session.contains(terminalID: focusedTerminalID) {
            self.focusedTerminalID = nil
        }
    }

    private func contextID(from sender: NSMenuItem) -> UUID? {
        guard let value = sender.representedObject as? String else { return nil }
        return UUID(uuidString: value)
    }

    private func sessionLocation(_ id: UUID) -> (workspace: Int, session: Int)? {
        for workspaceIndex in model.workspaces.indices {
            if let sessionIndex = model.workspaces[workspaceIndex].sessions.firstIndex(where: { $0.id == id }) {
                return (workspaceIndex, sessionIndex)
            }
        }
        return nil
    }

    private func normalizeSelection() {
        guard !model.workspaces.isEmpty else {
            model.selectedWorkspaceID = nil
            model.selectedSessionID = nil
            focusedTerminalID = nil
            return
        }
        guard let workspaceIndex = model.workspaces.firstIndex(where: { $0.id == model.selectedWorkspaceID }) else {
            let workspace = model.workspaces[0]
            model.selectedWorkspaceID = workspace.id
            model.selectedSessionID = workspace.sessions.first?.id
            focusedTerminalID = workspace.sessions.first?.terminalIDs.first
            return
        }
        let workspace = model.workspaces[workspaceIndex]
        guard let session = workspace.sessions.first(where: { $0.id == model.selectedSessionID }) else {
            model.selectedSessionID = workspace.sessions.first?.id
            focusedTerminalID = workspace.sessions.first?.terminalIDs.first
            return
        }
        if let focusedTerminalID, !session.contains(terminalID: focusedTerminalID) {
            self.focusedTerminalID = session.terminalIDs.first
        }
    }

    private var selectedWorkspace: Workspace? {
        guard let id = model.selectedWorkspaceID else { return nil }
        return model.workspaces.first(where: { $0.id == id })
    }

    private var selectedSession: WorkspaceSession? {
        guard let workspace = selectedWorkspace, let id = model.selectedSessionID else { return nil }
        return workspace.sessions.first(where: { $0.id == id })
    }

    @discardableResult
    private func mutateSession(_ id: UUID, _ mutation: (inout WorkspaceSession) -> Bool) -> Bool {
        guard let location = sessionLocation(id) else { return false }
        return mutation(&model.workspaces[location.workspace].sessions[location.session])
    }

    @objc private func toggleSidebar() {
        sidebarVisible.toggle()
        sidebar.isHidden = !sidebarVisible
        sidebarWidthConstraint?.isActive = sidebarVisible
        body.adjustSubviews()
        settingsTopConstraint?.constant = sidebarVisible ? 8 : 38
        paneLeadingConstraint?.constant = sidebarVisible ? 0 : 8
        paneTopConstraint?.constant = sidebarVisible ? 8 : 38
        emptyLeadingConstraint?.constant = sidebarVisible ? 0 : 8
        emptyTopConstraint?.constant = sidebarVisible ? 8 : 38
    }

    private func showPaneMenu(for terminalID: UUID) {
        guard let session = selectedSession, session.contains(terminalID: terminalID) else { return }
        focusedTerminalID = terminalID
        panes[terminalID]?.requestFocus()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(menuAction("Split right", selector: #selector(splitRightCommand), enabled: selectedSession != nil))
        menu.addItem(menuAction("Split below", selector: #selector(splitBelowCommand), enabled: selectedSession != nil))
        menu.addItem(menuAction("Toggle zoom", selector: #selector(toggleZoomCommand), enabled: selectedSession != nil))
        menu.addItem(.separator())
        menu.addItem(menuAction("Close pane", selector: #selector(closePaneCommand), enabled: selectedSession != nil))
        menu.addItem(menuAction("Close session", selector: #selector(closeFocusedSession), enabled: selectedSession != nil))
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func menuAction(_ title: String, selector: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func saveModel(delay: TimeInterval = 0) {
        guard !test && !preview else { return }
        saveScheduler?.submit(model, delay: delay)
    }

    private func presentPersistenceError(_ error: Error) {
        guard !persistenceErrorShown else { return }
        persistenceErrorShown = true
        let alert = NSAlert(error: error)
        alert.informativeText = "Review the saved state before moving or removing it. F7TTY left the original file untouched."
        alert.runModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        do {
            try saveScheduler?.flush()
        } catch {
            presentPersistenceError(error)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        if !test && !PerformanceDiagnostics.benchmark && !panes.isEmpty {
            guard confirmDestructiveAction(
                title: "Quit F7TTY and stop all terminals?",
                message: "Commands and jobs in these terminals will be terminated. Unsaved work may be lost.",
                action: "Stop terminals and quit"
            ) else { return .terminateCancel }
        }
        quitting = true
        guard f7tty_stop_descendants() == 0 else {
            quitting = false
            if test {
                fputs("SMOKE process cleanup FAIL\n", stderr)
                exit(1)
            }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "F7TTY could not finish stopping its terminals"
            alert.informativeText = "Some commands may already have stopped. The app will remain open because process discovery or signalling failed. Check your terminals before trying to quit again."
            alert.addButton(withTitle: "Keep F7TTY open")
            alert.runModal()
            return .terminateCancel
        }
        panes.values.forEach { $0.close() }
        if test && smokeFailed { exit(1) }
        return .terminateNow
    }

    func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "F7TTY")
        menu.addItem(appItem)
        let about = appItem.submenu!.addItem(withTitle: "About F7TTY", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let settings = appItem.submenu!.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appItem.submenu?.addItem(.separator())
        appItem.submenu?.addItem(withTitle: "Hide F7TTY", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appItem.submenu?.addItem(withTitle: "Quit F7TTY", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let terminalItem = NSMenuItem()
        terminalItem.submenu = NSMenu(title: "Terminal")
        menu.addItem(terminalItem)
        let newSessionItem = terminalItem.submenu!.addItem(withTitle: "New session", action: #selector(newSessionCommand), keyEquivalent: "t")
        let splitRightItem = terminalItem.submenu!.addItem(withTitle: "Split right", action: #selector(splitRightCommand), keyEquivalent: "d")
        let splitBelowItem = terminalItem.submenu!.addItem(withTitle: "Split below", action: #selector(splitBelowCommand), keyEquivalent: "d")
        newSessionItem.target = self
        splitRightItem.target = self
        splitBelowItem.target = self
        splitBelowItem.keyEquivalentModifierMask = [.command, .shift]
        let zoomItem = terminalItem.submenu!.addItem(withTitle: "Toggle pane zoom", action: #selector(toggleZoomCommand), keyEquivalent: "\r")
        zoomItem.target = self
        zoomItem.keyEquivalentModifierMask = [.command, .shift]
        let nextItem = terminalItem.submenu!.addItem(withTitle: "Next pane", action: #selector(nextPaneCommand), keyEquivalent: "\t")
        nextItem.target = self
        nextItem.keyEquivalentModifierMask = [.control]
        let previousItem = terminalItem.submenu!.addItem(withTitle: "Previous pane", action: #selector(previousPaneCommand), keyEquivalent: "\t")
        previousItem.target = self
        previousItem.keyEquivalentModifierMask = [.control, .shift]
        let equalizeItem = terminalItem.submenu!.addItem(withTitle: "Equalize splits", action: #selector(equalizeSplitsCommand), keyEquivalent: "=")
        equalizeItem.target = self
        equalizeItem.keyEquivalentModifierMask = [.command, .shift]
        addMoveMenuItems(to: terminalItem.submenu!)
        terminalItem.submenu!.addItem(.separator())
        for index in 1...9 {
            let item = terminalItem.submenu!.addItem(withTitle: "Select session \(index)", action: #selector(selectNumberedSession(_:)), keyEquivalent: String(index))
            item.target = self
            item.tag = index
        }

        let editItem = NSMenuItem()
        editItem.submenu = NSMenu(title: "Edit")
        menu.addItem(editItem)
        editItem.submenu?.addItem(withTitle: "Copy", action: #selector(GhosttyTerminalView.copy(_:)), keyEquivalent: "c")
        editItem.submenu?.addItem(withTitle: "Paste", action: #selector(GhosttyTerminalView.paste(_:)), keyEquivalent: "v")
        editItem.submenu?.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu?.addItem(.separator())
        let find = editItem.submenu!.addItem(withTitle: "Find…", action: #selector(findCommand), keyEquivalent: "f")
        find.target = self
        let findNext = editItem.submenu!.addItem(withTitle: "Find Next", action: #selector(findNextCommand), keyEquivalent: "g")
        findNext.target = self
        let findPrevious = editItem.submenu!.addItem(withTitle: "Find Previous", action: #selector(findPreviousCommand), keyEquivalent: "g")
        findPrevious.target = self
        findPrevious.keyEquivalentModifierMask = [.command, .shift]
        let viewItem = NSMenuItem()
        viewItem.submenu = NSMenu(title: "View")
        menu.addItem(viewItem)
        let sidebarItem = viewItem.submenu!.addItem(withTitle: "Hide sidebar", action: #selector(toggleSidebar), keyEquivalent: "b")
        sidebarItem.target = self
        let collapseItem = viewItem.submenu!.addItem(withTitle: "Collapse All Folders", action: #selector(collapseAllFolders), keyEquivalent: "b")
        collapseItem.target = self
        collapseItem.keyEquivalentModifierMask = [.command, .option]
        let paletteItem = viewItem.submenu!.addItem(withTitle: "Command Palette", action: #selector(showCommandPalette), keyEquivalent: "k")
        paletteItem.target = self
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        let closePaneItem = windowMenu.addItem(withTitle: "Close focused pane", action: #selector(closePaneCommand), keyEquivalent: "w")
        closePaneItem.target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }

    private func addMoveMenuItems(to menu: NSMenu) {
        let focusEntries: [(String, Selector, String)] = [
            ("Focus pane left", #selector(focusPaneLeftCommand), "\u{F702}"),
            ("Focus pane right", #selector(focusPaneRightCommand), "\u{F703}"),
            ("Focus pane up", #selector(focusPaneUpCommand), "\u{F700}"),
            ("Focus pane down", #selector(focusPaneDownCommand), "\u{F701}")
        ]
        for (title, selector, key) in focusEntries {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = [.command, .option]
            menu.addItem(item)
        }
        let entries: [(String, Selector, String)] = [
            ("Move pane left", #selector(movePaneLeftCommand), "\u{F702}"),
            ("Move pane right", #selector(movePaneRightCommand), "\u{F703}"),
            ("Move pane up", #selector(movePaneUpCommand), "\u{F700}"),
            ("Move pane down", #selector(movePaneDownCommand), "\u{F701}")
        ]
        for (title, selector, key) in entries {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = [.command, .option, .shift]
            menu.addItem(item)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if (settingsView != nil || commandPalette != nil) && menuItem.menu?.title == "Terminal" { return false }
        switch menuItem.action {
        case #selector(closePaneCommand):
            return settingsView == nil && commandPalette == nil && focusedTerminalID != nil
        case #selector(selectNumberedSession(_:)):
            return model.workspaces.flatMap(\.sessions).indices.contains(menuItem.tag - 1)
        case #selector(findCommand), #selector(findNextCommand), #selector(findPreviousCommand):
            return settingsView == nil && commandPalette == nil && focusedTerminalID != nil
        case #selector(toggleSidebar):
            menuItem.title = sidebarVisible ? "Hide sidebar" : "Show sidebar"
            return true
        case #selector(newSessionCommand):
            return selectedWorkspace != nil
        case #selector(splitRightCommand), #selector(splitBelowCommand), #selector(toggleZoomCommand),
             #selector(nextPaneCommand), #selector(previousPaneCommand), #selector(closeFocusedSession):
            return selectedSession != nil
        case #selector(equalizeSplitsCommand):
            return selectedSession?.tree.leafCount ?? 0 > 1
        case #selector(movePaneLeftCommand), #selector(movePaneRightCommand), #selector(movePaneUpCommand), #selector(movePaneDownCommand):
            return selectedSession?.tree.leafCount ?? 0 > 1
        default:
            return true
        }
    }

    @objc private func newSessionCommand() { newSession() }
    @objc private func selectNumberedSession(_ sender: NSMenuItem) {
        let sessions = model.workspaces.flatMap(\.sessions)
        guard sessions.indices.contains(sender.tag - 1) else { return }
        let session = sessions[sender.tag - 1]
        closeCommandPalette()
        closeSettings()
        if let workspace = model.workspaces.first(where: { $0.sessions.contains(where: { $0.id == session.id }) }) {
            collapsedWorkspaceIDs.remove(workspace.id)
        }
        selectSession(session.id)
        refreshSidebar()
    }
    @objc private func newSessionFromEmptyFolder(_ sender: SidebarRowButton) {
        guard let id = sender.itemID else { return }
        _ = addSession(to: id, name: nil, select: true, persist: true)
    }
    @objc private func findCommand() {
        guard settingsView == nil, commandPalette == nil, let id = focusedTerminalID else { return }
        panes[id]?.showSearch()
    }
    @objc private func findNextCommand() {
        guard settingsView == nil, commandPalette == nil, let id = focusedTerminalID else { return }
        panes[id]?.navigateSearch(next: true)
    }
    @objc private func findPreviousCommand() {
        guard settingsView == nil, commandPalette == nil, let id = focusedTerminalID else { return }
        panes[id]?.navigateSearch(next: false)
    }
    @objc private func newWorkspaceCommand() { newWorkspace() }
    @objc private func splitRightCommand() { splitFocused(direction: .right) }
    @objc private func splitBelowCommand() { splitFocused(direction: .down) }
    @objc private func toggleZoomCommand() {
        guard let focusedTerminalID else { return }
        toggleZoom(for: focusedTerminalID)
    }
    @objc private func nextPaneCommand() { cyclePane(forward: true) }
    @objc private func previousPaneCommand() { cyclePane(forward: false) }
    private func equalizeSplits() {
        guard let session = selectedSession, mutateSession(session.id, { $0.equalizeSplits() }) else { return }
        renderSelectedSession()
        saveModel()
    }
    @objc private func equalizeSplitsCommand() { equalizeSplits() }
    @objc private func movePaneLeftCommand() { moveFocused(direction: .left) }
    @objc private func focusPaneLeftCommand() { focusNeighbor(direction: .left) }
    @objc private func focusPaneRightCommand() { focusNeighbor(direction: .right) }
    @objc private func focusPaneUpCommand() { focusNeighbor(direction: .up) }
    @objc private func focusPaneDownCommand() { focusNeighbor(direction: .down) }

    private func focusNeighbor(direction: SplitDirection) {
        guard settingsView == nil, let session = selectedSession,
              session.zoomedTerminalID == nil, let source = focusedTerminalID else { return }
        var frames: [UUID: CGRect] = [:]
        for id in session.terminalIDs {
            guard let pane = panes[id], !pane.container.isHiddenOrHasHiddenAncestor else { continue }
            frames[id] = pane.container.convert(pane.container.bounds, to: nil)
        }
        guard let target = PaneNavigation.neighbor(of: source, direction: direction, frames: frames) else { return }
        focusedTerminalID = target
        panes[target]?.requestFocus()
    }
    @objc private func movePaneRightCommand() { moveFocused(direction: .right) }
    @objc private func movePaneUpCommand() { moveFocused(direction: .up) }
    @objc private func movePaneDownCommand() { moveFocused(direction: .down) }
    @objc private func closeFocusedSession() {
        guard let selectedSessionID = model.selectedSessionID else { return }
        let item = NSMenuItem()
        item.representedObject = selectedSessionID.uuidString
        removeSession(item)
    }
    @objc private func closePaneCommand() {
        guard settingsView == nil, commandPalette == nil, let focusedTerminalID else { return }
        closePane(focusedTerminalID)
    }
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.icon = Brand.image()
        alert.messageText = "F7TTY"
        alert.informativeText = "A native workspace for focused terminal sessions."
        alert.runModal()
    }

    private func showActivity() {
        guard let button = activityButton else { return }
        if activityPopover?.isShown == true { activityPopover?.performClose(nil); return }
        let controller = TerminalActivityViewController()
        controller.isTerminalAvailable = { [weak self] id in
            self?.model.workspaces.flatMap(\.sessions).contains(where: { $0.terminalIDs.contains(id) }) == true
        }
        controller.events = activity
        controller.onClear = { [weak self, weak controller] in
            self?.activity.removeAll()
            controller?.events = []
        }
        controller.onDismiss = { [weak self] in self?.activityPopover?.performClose(nil) }
        controller.onSelect = { [weak self] id in
            guard let self, let session = self.model.workspaces.flatMap(\.sessions).first(where: { $0.terminalIDs.contains(id) }) else { return }
            self.activityPopover?.performClose(nil)
            self.closeSettings()
            self.selectSession(session.id)
            self.focusPane(id)
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        activityController = controller
        activityPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        controller.view.window?.makeFirstResponder(controller.view)
        button.image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Recent activity")
    }

    @objc private func showSettings() {
        closeCommandPalette()
        guard settingsView == nil else { return }
        let workspaceID = selectedWorkspace?.id
        let view = AppearanceSettingsView(opacity: backgroundOpacity, appearanceMode: appearanceMode, appColor: selectedWorkspace?.appColor, onColorChange: { [weak self] color in
            guard let self, let index = self.model.workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
            self.model.workspaces[index].appColor = color
            self.refreshSidebar()
            self.saveModel()
        }, onChange: { [weak self] value in
            self?.applyBackgroundOpacity(value)
        }, onAppearanceChange: { [weak self] mode in
            self?.appearanceMode = mode
            self?.applyAppearanceMode()
            if let self, !self.test && !self.preview { UserDefaults.standard.set(mode, forKey: "appearanceMode") }
        })
        view.onDismiss = { [weak self] in self?.closeSettings() }
        settingsView = view
        renderSelectedSession()
        view.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(view)
        settingsTopConstraint = view.topAnchor.constraint(equalTo: canvas.topAnchor, constant: sidebarVisible ? 8 : 38)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -8),
            settingsTopConstraint!,
            view.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -8)
        ])
        window.makeFirstResponder(view)
        refreshSidebar()
    }

    private func closeSettings() {
        guard settingsView != nil else { return }
        settingsView?.removeFromSuperview()
        settingsView = nil
        settingsTopConstraint = nil
        refreshSidebar()
        renderSelectedSession()
    }

    @objc private func showCommandPalette() {
        if commandPalette != nil { closeCommandPalette(); return }
        var entries: [PaletteEntry] = []
        for workspace in model.workspaces {
            for session in workspace.sessions {
                let title = session.displayTitle(liveTitle: session.terminalIDs.first.flatMap { panes[$0]?.title.stringValue })
                entries.append(PaletteEntry(title: title, detail: workspace.name, shortcut: "", group: .sessions) { [weak self] in
                    if self?.settingsView != nil { self?.closeSettings() }
                    self?.selectSession(session.id)
                })
            }
            entries.append(PaletteEntry(title: workspace.name, detail: "Project", shortcut: "", group: .projects) { [weak self] in
                if self?.settingsView != nil { self?.closeSettings() }
                self?.collapsedWorkspaceIDs.remove(workspace.id)
                self?.selectWorkspace(workspace.id)
                self?.refreshSidebar()
            })
        }
        if selectedWorkspace != nil {
            entries.append(PaletteEntry(title: "New Terminal", detail: "Command", shortcut: "⌘T") { [weak self] in
                if self?.settingsView != nil { self?.closeSettings() }
                self?.newSession()
            })
        }
        entries.append(PaletteEntry(title: "Toggle Sidebar", detail: "Command", shortcut: "⌘B") { [weak self] in self?.toggleSidebar() })
        entries.append(PaletteEntry(title: "Settings", detail: "Command", shortcut: "⌘,") { [weak self] in self?.showSettings() })
        let palette = CommandPaletteView(entries: entries)
        palette.onDismiss = { [weak self] in self?.closeCommandPalette() }
        palette.onChoose = { [weak self] entry in self?.closeCommandPalette(); entry.action() }
        commandPalette = palette
        palette.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(palette, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            palette.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            palette.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            palette.topAnchor.constraint(equalTo: rootView.topAnchor),
            palette.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])
        window.makeFirstResponder(palette.field)
    }

    private func closeCommandPalette() {
        guard commandPalette != nil else { return }
        commandPalette?.removeFromSuperview()
        commandPalette = nil
        if let settingsView { window.makeFirstResponder(settingsView) }
        else if let id = focusedTerminalID { panes[id]?.requestFocus() }
    }

    private func applyBackgroundOpacity(_ value: Double) {
        backgroundOpacity = value.isFinite ? min(1, max(0, value)) : 1
        let translucent = backgroundOpacity < 1 || PerformanceDiagnostics.experiment("F7TTY_LEGACY_COMPOSITION")
        if translucent && backgroundBlur == nil {
            let blur = NSVisualEffectView(frame: rootView.bounds)
            blur.autoresizingMask = [.width, .height]
            blur.material = .underWindowBackground
            blur.blendingMode = .behindWindow
            blur.state = .active
            rootView.addSubview(blur, positioned: .below, relativeTo: body)
            backgroundBlur = blur
        } else if !translucent {
            backgroundBlur?.removeFromSuperview()
            backgroundBlur = nil
        }
        window.isOpaque = !translucent
        rootView.fillOpacity = translucent ? 0 : 1
        rootView.updateColors()
        window.backgroundColor = translucent ? .clear : (rootView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)) ?? .windowBackgroundColor)
        sidebar.fillOpacity = backgroundOpacity
        canvas.fillOpacity = backgroundOpacity
        if !test && !preview { UserDefaults.standard.set(backgroundOpacity, forKey: "backgroundOpacity") }
    }

    private func applyAppearanceMode() {
        let name: NSAppearance.Name?
        switch appearanceMode {
        case "light": name = .aqua
        case "system": name = nil
        default: name = .darkAqua
        }
        NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
        if window != nil { window.appearance = NSApp.appearance }
        if let host {
            host.setColorScheme(colorScheme(for: appearanceMode), appearance: window?.effectiveAppearance)
        }
    }

    private func colorScheme(for mode: String) -> GhosttyTerminalColorScheme {
        switch mode {
        case "light": return .light
        case "system": return .system
        default: return .dark
        }
    }

    private func splitFocused(direction: SplitDirection) {
        guard let focusedTerminalID else { return }
        splitPane(terminalID: focusedTerminalID, direction: direction)
    }

    private func cyclePane(forward: Bool) {
        guard let session = selectedSession else { return }
        let ids = session.terminalIDs
        guard ids.count > 1 else { return }
        let currentIndex = focusedTerminalID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let offset = forward ? 1 : -1
        let nextIndex = (currentIndex + offset + ids.count) % ids.count
        if session.zoomedTerminalID != nil {
            _ = mutateSession(session.id) { $0.zoomedTerminalID = ids[nextIndex]; return true }
            focusedTerminalID = ids[nextIndex]
            renderSelectedSession()
            return
        }
        focusPane(ids[nextIndex])
    }

    private func moveFocused(direction: SplitDirection) {
        guard let session = selectedSession,
              let focusedTerminalID,
              let index = session.terminalIDs.firstIndex(of: focusedTerminalID) else { return }
        let ids = session.terminalIDs
        let targetIndex: Int
        switch direction {
        case .left, .up:
            targetIndex = index - 1
        case .right, .down:
            targetIndex = index + 1
        }
        guard ids.indices.contains(targetIndex) else { NSSound.beep(); return }
        let zone: PaneDropZone
        switch direction {
        case .left: zone = .left
        case .right: zone = .right
        case .up: zone = .top
        case .down: zone = .bottom
        }
        _ = movePane(draggedID: focusedTerminalID, targetID: ids[targetIndex], zone: zone)
    }

    private func runSmokeTest() {
        guard let firstSession = selectedSession, let firstID = firstSession.terminalIDs.first else {
            smokeFailed = true
            print("SMOKE setup FAIL")
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let firstPane = self.panes[firstID] else { return }
            let frame = firstPane.terminal.frame
            let flushEdges = abs(frame.minX) < 0.5 && abs(frame.minY) < 0.5
                && abs(frame.maxX - firstPane.container.bounds.width) < 0.5
                && abs(frame.maxY - firstPane.header.frame.minY) < 0.5
                && firstPane.container.layer?.backgroundColor == NSColor.black.cgColor
            self.smokeFailed = self.smokeFailed || !flushEdges
            print("SMOKE black terminal panel has flush content edges \(flushEdges ? "PASS" : "FAIL")")
            self.applyBackgroundOpacity(0.7)
            let translucent = !self.window.isOpaque && self.backgroundBlur != nil && self.rootView.fillOpacity == 0
            self.captureSmokeWindow("translucent")
            self.applyBackgroundOpacity(1)
            let opaque = self.window.isOpaque && self.backgroundBlur == nil && self.rootView.isOpaque
            self.smokeFailed = self.smokeFailed || !translucent || !opaque
            print("SMOKE opacity transitions \(translucent && opaque ? "PASS" : "FAIL")")
            self.appearanceMode = "light"
            self.applyAppearanceMode()
            self.rootView.updateColors()
            let lightFill = NSColor(cgColor: self.rootView.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            self.appearanceMode = "dark"
            self.applyAppearanceMode()
            self.rootView.updateColors()
            let darkFill = NSColor(cgColor: self.rootView.layer!.backgroundColor!)!.usingColorSpace(.deviceRGB)!
            let appearancePass = lightFill.redComponent > 0.8 && darkFill.redComponent < 0.2
                && lightFill.alphaComponent == 1 && darkFill.alphaComponent == 1
            self.smokeFailed = self.smokeFailed || !appearancePass
            print("SMOKE opaque root follows appearance \(appearancePass ? "PASS" : "FAIL")")
            let tree = self.paneTreeView
            let terminalParent = firstPane.container.superview
            self.toggleSidebar()
            self.toggleSidebar()
            let stableSidebar = self.paneTreeView === tree && firstPane.container.superview === terminalParent
                && self.window.firstResponder === firstPane.terminal
            self.smokeFailed = self.smokeFailed || !stableSidebar
            print("SMOKE sidebar toggle keeps layout and focus \(stableSidebar ? "PASS" : "FAIL")")
            _ = self.mutateSession(firstSession.id) { $0.usesAutomaticTitle = true; return true }
            self.refreshSidebar()
            let row = self.automaticTitleRows[firstID]?.row
            firstPane.session.handle(action: .setTitle("  Efficient terminal  "))
            firstPane.session.handle(action: .setTitle("  Efficient terminal  "))
            let stableTitle = self.automaticTitleRows[firstID]?.row === row && row?.title == "Efficient terminal"
            self.smokeFailed = self.smokeFailed || !stableTitle
            print("SMOKE title update preserves sidebar row \(stableTitle ? "PASS" : "FAIL")")
            firstPane.session.handle(action: .setTitle("test@host: "))
            let fallbackTitle = self.selectedSession?.displayTitle(liveTitle: nil)
            let fallbackPass = self.automaticTitleRows[firstID]?.row === row && row?.title == fallbackTitle
            self.smokeFailed = self.smokeFailed || !fallbackPass
            print("SMOKE automatic title fallback \(fallbackPass ? "PASS" : "FAIL")")
            let queryProbe = TerminalSearchBar()
            var submittedQueries: [String] = []
            queryProbe.onQuery = { submittedQueries.append($0) }
            for query in ["a", "abc", "abc", "x"] {
                queryProbe.field.stringValue = query
                queryProbe.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
            }
            queryProbe.cancelPendingQuery()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let passed = submittedQueries == ["abc"]
                self.smokeFailed = self.smokeFailed || !passed
                print("SMOKE search deduplicates and cancels stale queries \(passed ? "PASS" : "FAIL")")
                _ = queryProbe
            }
            self.captureSmokeWindow("single")
            let replacement = NSRange(location: NSNotFound, length: 0)
            firstPane.terminal.unmarkText()
            firstPane.terminal.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: replacement)
            let compositionStarted = firstPane.terminal.hasMarkedText()
            firstPane.terminal.unmarkText()
            firstPane.terminal.unmarkText()
            firstPane.terminal.setMarkedText("printf", selectedRange: NSRange(location: 6, length: 0), replacementRange: replacement)
            firstPane.terminal.insertText("printf 'F7TTY_%s\\n\\a' SMOKE_OK", replacementRange: replacement)
            let compositionPass = compositionStarted && !firstPane.terminal.hasMarkedText()
            self.smokeFailed = self.smokeFailed || !compositionPass
            print("SMOKE composition cancel and commit \(compositionPass ? "PASS" : "FAIL")")
            firstPane.terminal.layer?.contentsScale = self.window.backingScaleFactor + 1
            firstPane.terminal.viewDidChangeBackingProperties()
            let scalePass = firstPane.terminal.layer?.contentsScale == self.window.backingScaleFactor
            self.smokeFailed = self.smokeFailed || !scalePass
            print("SMOKE backing layer scale repair \(scalePass ? "PASS" : "FAIL")")
            let enter = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: self.window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            )!
            firstPane.terminal.keyDown(with: enter)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                firstPane.showSearch(query: "F7TTY_SMOKE_OK")
                _ = firstPane.session.perform(action: "search:F7TTY_SMOKE_OK")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let outputPane = self.panes[firstID] else { return }
                _ = outputPane.session.perform(action: "select_all")
                let outputPassed = outputPane.session.copySelection()?.contains("F7TTY_SMOKE_OK") == true
                self.smokeFailed = self.smokeFailed || !outputPassed
                print(outputPassed ? "SMOKE terminal output PASS" : "SMOKE terminal output FAIL")
                let activityPassed = self.activity.contains { $0.terminalID == firstID && $0.title == "Terminal bell" }
                self.smokeFailed = self.smokeFailed || !activityPassed
                print("SMOKE terminal bell event \(activityPassed ? "PASS" : "FAIL")")
                let searchPassed = outputPane.session.state.searchTotal > 0
                self.smokeFailed = self.smokeFailed || !searchPassed
                print("SMOKE terminal search \(searchPassed ? "PASS" : "FAIL")")
                _ = outputPane.session.perform(action: "end_search")

                let originalSession = outputPane.session
                let originalView = outputPane.terminal
                self.showCommandPalette()
                let paletteShown = self.commandPalette != nil && !outputPane.container.isHidden
                let paletteResponder = self.window.firstResponder
                let findItem = NSMenuItem(title: "Find", action: #selector(self.findCommand), keyEquivalent: "f")
                let terminalMenu = NSMenu(title: "Terminal")
                let splitItem = NSMenuItem(title: "Split right", action: #selector(self.splitRightCommand), keyEquivalent: "d")
                terminalMenu.addItem(splitItem)
                self.findCommand()
                let paletteOwnsCommands = !self.validateMenuItem(findItem)
                    && !self.validateMenuItem(splitItem)
                    && self.window.firstResponder === paletteResponder
                self.smokeFailed = self.smokeFailed || !paletteOwnsCommands
                print("SMOKE palette blocks underlying terminal commands \(paletteOwnsCommands ? "PASS" : "FAIL")")
                self.closeCommandPalette()
                let paletteRestored = paletteShown && self.commandPalette == nil
                    && self.window.firstResponder === originalView
                    && self.panes[firstID]?.session === originalSession
                self.smokeFailed = self.smokeFailed || !paletteRestored
                print("SMOKE palette preserves terminal \(paletteRestored ? "PASS" : "FAIL")")
                self.showSettings()
                let settingsHidden = outputPane.container.isHidden && self.settingsView != nil
                self.closeSettings()
                let settingsRestored = settingsHidden && !outputPane.container.isHidden
                    && self.panes[firstID]?.session === originalSession
                    && self.panes[firstID]?.terminal === originalView
                self.smokeFailed = self.smokeFailed || !settingsRestored
                print("SMOKE settings preserve terminal \(settingsRestored ? "PASS" : "FAIL")")
                if let workspaceID = self.model.selectedWorkspaceID {
                    let selectedID = self.model.selectedSessionID
                    self.toggleWorkspaceExpansion(workspaceID)
                    let collapsed = self.collapsedWorkspaceIDs.contains(workspaceID)
                        && self.model.selectedSessionID == selectedID
                        && !outputPane.container.isHidden
                        && self.panes[firstID]?.session === originalSession
                    self.toggleWorkspaceExpansion(workspaceID)
                    self.smokeFailed = self.smokeFailed || !collapsed
                    print("SMOKE folder collapse preserves terminal \(collapsed ? "PASS" : "FAIL")")
                }
                self.focusedTerminalID = firstID
                self.splitPane(terminalID: firstID, direction: .right)
                guard let splitSession = self.selectedSession,
                      let secondID = splitSession.terminalIDs.first(where: { $0 != firstID }),
                      let secondPane = self.panes[secondID] else {
                    self.smokeFailed = true
                    print("SMOKE two surfaces FAIL")
                    self.finishSmokeTest()
                    return
                }
                let twoSurfaces = originalSession.surface != nil && secondPane.session.surface != nil
                self.smokeFailed = self.smokeFailed || !twoSurfaces
                print("SMOKE two surfaces \(twoSurfaces ? "PASS" : "FAIL")")

                let treeBeforeZoom = splitSession.tree
                self.window.contentView?.layoutSubtreeIfNeeded()
                self.focusedTerminalID = firstID
                self.focusNeighbor(direction: .right)
                let focusedRight = self.focusedTerminalID == secondID
                    && self.window.firstResponder === secondPane.terminal
                    && self.selectedSession?.tree == treeBeforeZoom
                self.focusNeighbor(direction: .left)
                let focusedLeft = self.focusedTerminalID == firstID
                    && self.window.firstResponder === originalView
                self.smokeFailed = self.smokeFailed || !focusedRight || !focusedLeft
                print("SMOKE directional focus \(focusedRight && focusedLeft ? "PASS" : "FAIL")")
                self.toggleZoom(for: firstID)
                let identityAfterZoom = self.panes[firstID]?.session === originalSession
                    && self.panes[firstID]?.terminal === originalView
                    && self.selectedSession?.tree == treeBeforeZoom
                self.smokeFailed = self.smokeFailed || !identityAfterZoom
                print("SMOKE zoom identity \(identityAfterZoom ? "PASS" : "FAIL")")
                self.toggleZoom(for: firstID)

                let moved = self.movePane(draggedID: secondID, targetID: firstID, zone: .left)
                let identityAfterMove = moved
                    && self.panes[firstID]?.session === originalSession
                    && self.panes[secondID]?.terminal === secondPane.terminal
                self.smokeFailed = self.smokeFailed || !identityAfterMove
                print("SMOKE move identity \(identityAfterMove ? "PASS" : "FAIL")")

                guard let workspaceID = self.model.selectedWorkspaceID else {
                    self.smokeFailed = true
                    self.finishSmokeTest()
                    return
                }
                self.showSettings()
                _ = self.addSession(to: workspaceID, name: "Hidden test", select: true, persist: false)
                let newSessionVisible = self.settingsView == nil
                    && self.selectedSession?.terminalIDs.allSatisfy { self.panes[$0]?.container.isHidden == false } == true
                    && self.panes[firstID]?.session === originalSession
                self.smokeFailed = self.smokeFailed || !newSessionVisible
                print("SMOKE new session leaves settings \(newSessionVisible ? "PASS" : "FAIL")")
                let hidden = self.panes[firstID]?.container.isHidden == true
                print("SMOKE hidden pane \(hidden ? "PASS" : "FAIL")")
                self.smokeFailed = self.smokeFailed || !hidden
                let shortcut = NSMenuItem()
                shortcut.tag = 1
                self.selectNumberedSession(shortcut)
                let shortcutSelected = self.selectedSession?.id == splitSession.id
                    && self.panes[firstID]?.session === originalSession
                self.smokeFailed = self.smokeFailed || !shortcutSelected
                print("SMOKE numbered session selection \(shortcutSelected ? "PASS" : "FAIL")")
                let shownAgain = self.panes[firstID]?.container.isHidden == false
                print("SMOKE show pane \(shownAgain ? "PASS" : "FAIL")")
                self.smokeFailed = self.smokeFailed || !shownAgain
                if let other = self.selectedWorkspace?.sessions.first(where: { $0.id != splitSession.id }) {
                    let responder = self.window.firstResponder
                    self.reorderSidebar(source: splitSession.id, target: other.id, after: true)
                    let preserved = self.selectedSession?.id == splitSession.id
                        && self.panes[firstID]?.session === originalSession
                        && self.panes[firstID]?.terminal === originalView
                        && self.window.firstResponder === responder
                        && self.panes[firstID]?.container.isHidden == false
                    self.smokeFailed = self.smokeFailed || !preserved
                    print("SMOKE sidebar reorder preserves live surface and focus \(preserved ? "PASS" : "FAIL")")
                }
                self.splitPane(terminalID: firstID, direction: .down)
                self.finishSmokeTest()
            }
        }
    }

    private func benchmarkCounts() -> [String: Int] {
        var counts = PerformanceDiagnostics.counts
        for snapshot in [host.profilingSnapshot()] + panes.values.flatMap({ [$0.session.profilingSnapshot(), $0.terminal.profilingSnapshot()] }) {
            counts.merge(snapshot, uniquingKeysWith: +)
        }
        return counts
    }

    /// SIGUSR1 finishes only this disposable benchmark process. No polling timer
    /// or diagnostic output runs in the measured interval.
    private func runBenchmark() {
        guard let path = ProcessInfo.processInfo.environment["F7TTY_BENCHMARK_REPORT"] else {
            NSApp.terminate(nil)
            return
        }
        if let screen = window.screen ?? NSScreen.main { window.setFrame(screen.visibleFrame, display: true) }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        benchmarkFinishSignal = source
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var measured = self.benchmarkCounts()
            for (key, value) in self.benchmarkInitialCounts { measured[key, default: 0] -= value }
            let pane = self.selectedSession?.terminalIDs.first.flatMap { self.panes[$0] }
            let size = pane?.session.surface.map { ghostty_surface_size($0) }
            let report: [String: Any] = [
                "seconds": ProcessInfo.processInfo.systemUptime - self.benchmarkStartTime,
                "counters": measured,
                "windowOpaque": self.window.isOpaque,
                "blurAttached": self.backgroundBlur != nil,
                "paneClipped": pane?.container.layer?.masksToBounds ?? false,
                "surfaceWidth": pane?.terminal.bounds.width ?? 0,
                "surfaceHeight": pane?.terminal.bounds.height ?? 0,
                "columns": size?.columns ?? 0,
                "rows": size?.rows ?? 0,
                "pixelWidth": size?.width_px ?? 0,
                "pixelHeight": size?.height_px ?? 0,
                "cellWidth": size?.cell_width_px ?? 0,
                "cellHeight": size?.cell_height_px ?? 0,
                "title": pane?.title.stringValue ?? "",
                "backingScale": self.window.backingScaleFactor,
                "rendererLayer": pane?.terminal.layer.map { String(describing: type(of: $0)) } ?? "none"
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            } catch { fputs("Benchmark report failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
        }
        source.resume()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.benchmarkInitialCounts = self.benchmarkCounts()
            self.benchmarkStartTime = ProcessInfo.processInfo.systemUptime
            let ready: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "windowID": self.window.windowNumber]
            do {
                let data = try JSONSerialization.data(withJSONObject: ready)
                try data.write(to: URL(fileURLWithPath: path + ".ready"), options: .atomic)
            } catch { fputs("Benchmark readiness failed: \(error)\n", stderr); NSApp.terminate(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, !self.quitting else { return }
            fputs("Benchmark timed out\n", stderr)
            NSApp.terminate(nil)
        }
    }

    private func finishSmokeTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.window.contentView?.layoutSubtreeIfNeeded()
            let usable = self.selectedSession?.terminalIDs.allSatisfy {
                guard let pane = self.panes[$0] else { return false }
                return pane.container.bounds.width > 150 && pane.container.bounds.height > 100
            } == true
            self.smokeFailed = self.smokeFailed || !usable
            print("SMOKE nested pane geometry \(usable ? "PASS" : "FAIL")")
            self.captureSmokeWindow("nested")
            self.toggleSidebar()
            self.window.contentView?.layoutSubtreeIfNeeded()
            func balancedMargins(_ view: NSView?) -> Bool {
                guard let view else { return false }
                return abs(view.frame.minX - 8) < 0.5 && abs(self.canvas.bounds.width - view.frame.maxX - 8) < 0.5
            }
            let splitMargins = balancedMargins(self.paneTreeView)
            self.captureSmokeWindow("collapsed-sidebar")
            var zoomMargins = false
            if let id = self.focusedTerminalID {
                self.toggleZoom(for: id)
                self.window.contentView?.layoutSubtreeIfNeeded()
                zoomMargins = balancedMargins(self.panes[id]?.container)
                self.captureSmokeWindow("collapsed-sidebar-zoom")
                self.toggleZoom(for: id)
            }
            self.toggleSidebar()
            self.window.contentView?.layoutSubtreeIfNeeded()
            let expandedMargin = abs(self.paneTreeView?.frame.minX ?? -1) < 0.5
            let marginsPass = splitMargins && zoomMargins && expandedMargin
            self.smokeFailed = self.smokeFailed || !marginsPass
            print("SMOKE sidebar margins in split, zoom and expanded layouts \(marginsPass ? "PASS" : "FAIL")")
            if CommandLine.arguments.contains("--inspect-smoke"), !self.smokeFailed {
                self.showActivity()
                return
            }
            while self.selectedSession != nil { self.closeFocusedSession() }
            self.window.setContentSize(NSSize(width: 650, height: 400))
            self.window.contentView?.layoutSubtreeIfNeeded()
            let emptyPass = !self.emptyState.isHidden && self.paneTreeView == nil && self.panes.isEmpty
                && !self.model.workspaces.isEmpty && self.model.workspaces.allSatisfy { $0.sessions.isEmpty }
                && self.emptyState.bounds.width > 200 && self.emptyState.bounds.height > 300
            self.toggleSidebar()
            self.window.contentView?.layoutSubtreeIfNeeded()
            let emptyMargins = balancedMargins(self.emptyState)
            self.toggleSidebar()
            self.smokeFailed = self.smokeFailed || !emptyPass || !emptyMargins
            print("SMOKE closing all sessions keeps framed empty workspace \(emptyPass && emptyMargins ? "PASS" : "FAIL")")
            self.captureSmokeWindow("empty-workspace")
            NSApp.terminate(self)
        }
    }

    private func captureSmokeWindow(_ name: String) {
        guard test, let index = CommandLine.arguments.firstIndex(of: "--capture-directory"),
              CommandLine.arguments.count > index + 1 else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let output = URL(fileURLWithPath: CommandLine.arguments[index + 1]).appendingPathComponent("\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
        do {
            try capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus != 0 { smokeFailed = true }
        } catch {
            smokeFailed = true
            print("SMOKE screenshot FAIL: \(error.localizedDescription)")
        }
    }
}

private extension NSPasteboard.PasteboardType {
    static let f7ttyPane = PaneContainerView.panePasteboardType
}

@MainActor
enum Brand {
    static func image() -> NSImage {
        // Preserve FunnySoft's vector geometry on a padded, softly lit tile.
        let source = try! String(contentsOf: Assets.bundle.url(forResource: "funnysoft", withExtension: "svg", subdirectory: "Resources")!, encoding: .utf8)
        let paths = try! NSRegularExpression(pattern: "d=\"([^\"]+)\"")
        let tokens = try! NSRegularExpression(pattern: "[MLCHZ]|-?[0-9]+(?:\\.[0-9]+)?")
        let image = NSImage(size: NSSize(width: 512, height: 512))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 512, height: 512).fill(using: .copy)
        let tile = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 424, height: 424), xRadius: 94, yRadius: 94)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowBlurRadius = 10
        shadow.set()
        NSColor.black.setFill()
        tile.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.025, alpha: 1), ending: NSColor(white: 0.16, alpha: 1))!.draw(in: tile, angle: 90)
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        tile.lineWidth = 3
        NSColor.white.withAlphaComponent(0.2).setStroke()
        tile.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let inset = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 416, height: 416), xRadius: 90, yRadius: 90)
        inset.lineWidth = 1
        NSColor.black.withAlphaComponent(0.55).setStroke()
        inset.stroke()
        let transform = AffineTransform(translationByX: 112, byY: 400)
        var scaled = transform
        scaled.scale(x: 1.152, y: -1.152)
        let mark = NSBezierPath()
        for match in paths.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let text = String(source[Range(match.range(at: 1), in: source)!])
            let values = tokens.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { String(text[Range($0.range, in: text)!]) }
            var i = 0
            let path = NSBezierPath()
            func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(values[i])!) }
            func point() -> NSPoint { NSPoint(x: number(), y: number()) }
            while i < values.count {
                let command = values[i]; i += 1
                switch command {
                case "M": path.move(to: point())
                case "L": path.line(to: point())
                case "H": path.line(to: NSPoint(x: number(), y: path.currentPoint.y))
                case "C": let a = point(); let b = point(); let c = point(); path.curve(to: c, controlPoint1: a, controlPoint2: b)
                case "Z": path.close()
                default: break
                }
            }
            path.transform(using: scaled)
            mark.append(path)
        }
        NSGraphicsContext.saveGraphicsState()
        let relief = NSShadow()
        relief.shadowColor = NSColor.black.withAlphaComponent(0.85)
        relief.shadowOffset = NSSize(width: 0, height: -3)
        relief.shadowBlurRadius = 3
        relief.set()
        NSColor(white: 0.85, alpha: 1).setFill()
        mark.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(white: 0.77, alpha: 1), ending: .white)!.draw(in: mark, angle: 90)
        image.unlockFocus()
        return image
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = F7TTYAppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
