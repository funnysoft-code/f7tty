import AppKit

@MainActor
final class TerminalSearchBar: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    private let count = NSTextField(labelWithString: "")
    var onQuery: ((String) -> Void)?
    var onNavigate: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    var ownsKeyboardFocus: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === field { return true }
        guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
        return editor.delegate === field
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor
        layer?.cornerRadius = 6
        field.placeholderString = "Find"
        field.font = .systemFont(ofSize: 12)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.setAccessibilityLabel("Find")
        count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        count.widthAnchor.constraint(equalToConstant: 46).isActive = true
        let previous = ActionButton("Previous Match", symbol: "chevron.up") { [weak self] in self?.onNavigate?(false) }
        let next = ActionButton("Next Match", symbol: "chevron.down") { [weak self] in self?.onNavigate?(true) }
        let done = ActionButton("Done", symbol: "xmark") { [weak self] in self?.onClose?() }
        [previous, next, done].forEach {
            $0.controlDimension = 20
            $0.widthAnchor.constraint(equalToConstant: 20).isActive = true
        }
        let stack = NSStackView(views: [field, count, previous, next, done])
        stack.spacing = 2
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        // Keep real click targets in narrow splits; the count is secondary to the query.
        count.isHidden = bounds.width < 224
        super.layout()
    }

    func update(total: Int, selected: Int?) {
        count.stringValue = field.stringValue.isEmpty ? "" : "\(selected.map { $0 + 1 } ?? 0)/\(max(0, total))"
    }

    func controlTextDidChange(_ obj: Notification) { onQuery?(field.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onClose?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onNavigate?(!NSEvent.modifierFlags.contains(.shift))
            return true
        }
        return false
    }
}
