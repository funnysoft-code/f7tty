import AppKit
import GhosttyKit

struct TerminalActivity: Identifiable, Equatable {
    let id = UUID()
    let terminalID: UUID
    let title: String
    let detail: String

    static func event(_ action: GhosttyTerminalAction, terminalID: UUID) -> TerminalActivity? {
        switch action {
        case .ringBell:
            return Self(terminalID: terminalID, title: "Terminal bell", detail: "The terminal requested attention.")
        case .desktopNotification(let title, let body):
            return Self(terminalID: terminalID, title: String(title.prefix(160)), detail: String(body.prefix(320)))
        case .childExited(let code):
            return Self(terminalID: terminalID, title: "Terminal exited", detail: "Exit status \(code)")
        default:
            return nil
        }
    }
}

@MainActor
final class ActivityContentView: NSView {
    var onDismiss: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor
final class TerminalActivityViewController: NSViewController {
    var isTerminalAvailable: (UUID) -> Bool = { _ in true }
    private(set) var showsAll = false
    func showAll() { showsAll = true; if isViewLoaded { render() } }
    var events: [TerminalActivity] = [] { didSet { if isViewLoaded { render() } } }
    var onSelect: ((UUID) -> Void)?
    var onClear: (() -> Void)?
    var onDismiss: (() -> Void)?
    override func loadView() {
        let content = ActivityContentView(frame: NSRect(x: 0, y: 0, width: 370, height: 100))
        content.onDismiss = { [weak self] in self?.onDismiss?() }
        view = content
        render()
    }
    private func render() {
        view.subviews.forEach { $0.removeFromSuperview() }
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let title = NSTextField(labelWithString: "Recent activity")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(title)
        if events.isEmpty {
            let empty = NSTextField(labelWithString: "No recent terminal activity")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
        } else {
            let list = NSStackView()
            list.orientation = .vertical
            list.alignment = .leading
            list.spacing = 8
            list.translatesAutoresizingMaskIntoConstraints = false
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.automaticallyAdjustsContentInsets = false
            let document = SidebarDocumentView()
            document.translatesAutoresizingMaskIntoConstraints = false
            scroll.documentView = document
            document.addSubview(list)
            stack.addArrangedSubview(scroll)
            let visibleEvents = showsAll ? events : Array(events.prefix(6))
            NSLayoutConstraint.activate([
                scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scroll.heightAnchor.constraint(equalToConstant: CGFloat(min(6, visibleEvents.count) * 36)),
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
                list.topAnchor.constraint(equalTo: document.topAnchor),
                list.bottomAnchor.constraint(equalTo: document.bottomAnchor)
            ])
            for event in visibleEvents {
                let button = ActionButton(event.title) { [weak self] in self?.onSelect?(event.terminalID) }
                button.alignment = .left
                button.lineBreakMode = .byTruncatingTail
                button.isEnabled = isTerminalAvailable(event.terminalID)
                button.toolTip = event.detail + (button.isEnabled ? "" : "\nThis terminal has been closed.")
                list.addArrangedSubview(button)
                button.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            }
            if !showsAll && events.count > 6 {
                stack.addArrangedSubview(ActionButton("All recent activity (\(events.count))") { [weak self] in self?.showAll() })
            }
            stack.addArrangedSubview(ActionButton("Clear recent activity") { [weak self] in self?.onClear?() })
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14)
        ])
        preferredContentSize = NSSize(width: 370, height: events.isEmpty ? 90 : 84 + min(6, events.count) * 36 + (!showsAll && events.count > 6 ? 36 : 0))
    }
}
