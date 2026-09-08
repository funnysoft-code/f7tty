import AppKit

/// Settings stay in the workspace window; terminal surfaces remain alive and occluded.
@MainActor
final class AppearanceSettingsView: AppearancePanel {
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let percentage = NSTextField(labelWithString: "100%")
    private let onChange: (Double) -> Void
    private let onAppearanceChange: (String) -> Void
    var onDismiss: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    init(opacity: Double, appearanceMode: String, appColor: String? = nil, onColorChange: @escaping (String?) -> Void = { _ in }, onChange: @escaping (Double) -> Void, onAppearanceChange: @escaping (String) -> Void) {
        self.onChange = onChange
        self.onAppearanceChange = onAppearanceChange
        super.init(frame: .zero)
        wantsLayer = true
        darkFill = NSColor(white: 0.105, alpha: 1)
        lightFill = NSColor(white: 0.985, alpha: 1)
        updateColors()
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.23, alpha: 1).cgColor

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = SidebarDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        addSubview(scroll)
        document.addSubview(stack)
        let fittedWidth = document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        fittedWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            fittedWidth,
            document.widthAnchor.constraint(greaterThanOrEqualToConstant: 600),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 88),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -88),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        func text(_ value: String, size: CGFloat, color: NSColor = .labelColor) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value)
            field.font = .systemFont(ofSize: size)
            field.textColor = color
            return field
        }
        let breadcrumb = text("Settings  /  Appearance", size: 12, color: .secondaryLabelColor)
        stack.addArrangedSubview(breadcrumb)
        stack.setCustomSpacing(36, after: breadcrumb)
        let heading = text("Appearance", size: 22)
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(heading)
        let description = text("Customize how F7TTY looks and feels.", size: 13, color: .secondaryLabelColor)
        stack.addArrangedSubview(description)
        stack.setCustomSpacing(36, after: description)
        stack.addArrangedSubview(text("Mode", size: 14))
        stack.addArrangedSubview(text("Choose whether F7TTY follows macOS or stays light or dark.", size: 13, color: .secondaryLabelColor))
        let mode = NSSegmentedControl(labels: ["System", "Light", "Dark"], trackingMode: .selectOne, target: self, action: #selector(modeChanged(_:)))
        mode.segmentStyle = .rounded
        mode.selectedSegment = ["system", "light", "dark"].firstIndex(of: appearanceMode) ?? 0
        mode.setAccessibilityLabel("Appearance mode")
        mode.widthAnchor.constraint(equalToConstant: 195).isActive = true
        mode.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let modeRow = NSStackView(views: [NSView(), mode])
        modeRow.orientation = .horizontal
        modeRow.spacing = 12
        stack.addArrangedSubview(modeRow)
        modeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(36, after: modeRow)
        stack.addArrangedSubview(text("App color", size: 14))
        stack.addArrangedSubview(text("Choose a background color for this workspace.", size: 13, color: .secondaryLabelColor))
        let colors = WorkspaceColor.allCases.map(WorkspaceColorButton.init)
        let selected = appColor.flatMap(WorkspaceColor.init(rawValue:)) ?? .standard
        for button in colors {
            button.state = button.color == selected ? .on : .off
            button.onChoose = { [weak button] in
                guard let button else { return }
                for sibling in button.superview?.subviews.compactMap({ $0 as? WorkspaceColorButton }) ?? [] {
                    sibling.state = sibling === button ? .on : .off
                    sibling.needsDisplay = true
                }
                onColorChange(button.color == .standard ? nil : button.color.rawValue)
            }
        }
        let colorsRow = NSStackView(views: colors)
        colorsRow.orientation = .horizontal
        colorsRow.spacing = 8
        stack.addArrangedSubview(colorsRow)
        stack.setCustomSpacing(36, after: colorsRow)
        stack.addArrangedSubview(text("Transparency", size: 14))
        stack.addArrangedSubview(text("Adjust the window background. Below 100%, native macOS blur shows through. Terminal text and surfaces stay fully opaque.", size: 13, color: .secondaryLabelColor))

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.wantsLayer = true
        // Native separators and labels follow appearance; avoid a fixed dark row.
        row.layer?.backgroundColor = NSColor.clear.cgColor
        row.layer?.cornerRadius = 6
        row.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        row.addArrangedSubview(text("Background", size: 13))
        row.addArrangedSubview(NSView())
        slider.doubleValue = opacity
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Background opacity")
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        row.addArrangedSubview(slider)
        percentage.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentage.alignment = .right
        percentage.widthAnchor.constraint(equalToConstant: 40).isActive = true
        row.addArrangedSubview(percentage)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let reset = ActionButton("Revert to default") { [weak self] in
            self?.slider.doubleValue = 1
            self?.changed()
        }
        stack.addArrangedSubview(reset)
        percentage.stringValue = "\(Int(opacity * 100))%"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func changed() {
        percentage.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
        onChange(slider.doubleValue)
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let modes = ["system", "light", "dark"]
        guard modes.indices.contains(sender.selectedSegment) else { return }
        onAppearanceChange(modes[sender.selectedSegment])
    }
}
