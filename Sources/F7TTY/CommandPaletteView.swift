import AppKit

@MainActor
struct PaletteEntry {
    enum Group: String, CaseIterable { case sessions = "Sessions", projects = "Projects", commands = "Commands" }
    let title: String
    let detail: String
    let shortcut: String
    var group: Group = .commands
    let action: () -> Void

    static func matching(_ entries: [PaletteEntry], query: String) -> [PaletteEntry] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return entries.filter { entry in
            words.allSatisfy { word in
                "\(entry.title) \(entry.detail)".localizedStandardContains(String(word))
            }
        }
    }
}

@MainActor
final class CommandPaletteView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let field = NSTextField()
    let table = NSTableView()
    private let entries: [PaletteEntry]
    private var listHeight: NSLayoutConstraint?
    private let emptyLabel = NSTextField(labelWithString: "No results")
    private(set) var filtered: [PaletteEntry]
    private var rows: [(heading: String?, entry: Int?)] = []
    var onDismiss: (() -> Void)?
    var onChoose: ((PaletteEntry) -> Void)?

    init(entries: [PaletteEntry]) {
        self.entries = entries
        filtered = entries
        super.init(frame: .zero)
        let card = AppearancePanel()
        card.wantsLayer = true
        card.darkFill = NSColor(white: 0.105, alpha: 1)
        card.lightFill = NSColor(white: 0.985, alpha: 1)
        card.updateColors()
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor(white: 0.25, alpha: 1).cgColor
        card.shadow = NSShadow()
        card.shadow?.shadowBlurRadius = 28
        card.shadow?.shadowOffset = NSSize(width: 0, height: -10)
        card.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.55)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        field.placeholderString = "Search sessions, projects, commands…"
        field.setAccessibilityLabel("Search sessions, projects, commands")
        field.font = .systemFont(ofSize: 13)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(field)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(separator)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 29
        table.intercellSpacing = .zero
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(chooseClickedRow)
        table.setAccessibilityLabel("Matching sessions and commands")
        scroll.documentView = table
        card.addSubview(scroll)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        let width = card.widthAnchor.constraint(equalToConstant: 560)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            width,
            card.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -32),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 140),
            card.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            field.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            field.heightAnchor.constraint(equalToConstant: 20),
            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6)
        ])
        let height = scroll.heightAnchor.constraint(equalToConstant: min(348, CGFloat(max(1, filtered.count)) * 29))
        height.priority = .defaultHigh
        height.isActive = true
        listHeight = height
        selectFirst()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { onDismiss?() }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    func controlTextDidChange(_ obj: Notification) {
        filtered = PaletteEntry.matching(entries, query: field.stringValue)
        selectFirst()
    }

    private func selectFirst() {
        rows = []
        for group in PaletteEntry.Group.allCases {
            let indices = filtered.indices.filter { filtered[$0].group == group }
            guard !indices.isEmpty else { continue }
            rows.append((group.rawValue, nil))
            rows += indices.map { (nil, $0) }
        }
        table.reloadData()
        listHeight?.constant = min(348, CGFloat(max(1, rows.count)) * 29)
        emptyLabel.isHidden = !filtered.isEmpty
        table.selectRowIndexes(rows.firstIndex(where: { $0.entry != nil }).map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        case #selector(NSResponder.insertNewline(_:)): chooseSelected()
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        default: return false
        }
        return true
    }

    private func moveSelection(_ delta: Int) {
        let selectable = rows.indices.filter { rows[$0].entry != nil }
        guard !selectable.isEmpty else { return }
        let index = selectable.firstIndex(of: table.selectedRow) ?? 0
        let row = selectable[min(selectable.count - 1, max(0, index + delta))]
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func chooseSelected() {
        guard rows.indices.contains(table.selectedRow), let index = rows[table.selectedRow].entry else { return }
        onChoose?(filtered[index])
    }

    @objc private func chooseClickedRow() { chooseSelected() }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].entry != nil }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { rows[row].heading != nil }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaletteRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let index = rows[row].entry else {
            let cell = NSTableCellView()
            let label = NSTextField(labelWithString: rows[row].heading ?? "")
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            cell.textField = label
            return cell
        }
        let entry = filtered[index]
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: entry.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        let shortcut = NSTextField(labelWithString: entry.shortcut)
        shortcut.font = .systemFont(ofSize: 11)
        shortcut.textColor = .secondaryLabelColor
        let detail = NSTextField(labelWithString: entry.detail)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        detail.lineBreakMode = .byTruncatingTail
        for label in [title, shortcut, detail] {
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -8),
            shortcut.trailingAnchor.constraint(equalTo: detail.leadingAnchor, constant: -12),
            detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            detail.widthAnchor.constraint(equalToConstant: 90)
        ])
        cell.textField = title
        return cell
    }
}

@MainActor
private final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor(white: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}
