import AppKit
import EasyPasteCore

@MainActor
final class FormatPickerView: NSView {
    var onPick: ((ClipboardTransform) -> Void)?
    var onCancel: (() -> Void)?

    private let stack = NSStackView()
    private let visualEffect = NSVisualEffectView()
    private var rows: [FormatRow] = []
    private var highlightedIndex = 0

    /// 计算给定 item 上可用的 transform 列表（始终包含 .original 与 .plain）。
    static func candidateTransforms(for item: ClipboardItem) -> [ClipboardTransform] {
        if item.kind == .image {
            return []
        }

        let text = item.text ?? ""
        var result: [ClipboardTransform] = [.original]

        if item.kind == .json || ClipboardFormatter.isJSON(text) {
            result.append(.json)
        }
        if item.kind == .xml || ClipboardFormatter.isXML(text) {
            result.append(.xml)
        }
        if item.kind == .yaml || ClipboardFormatter.isYAML(text) {
            result.append(.yaml)
        }
        if item.kind == .sql || ClipboardFormatter.isSQL(text) {
            result.append(.sql)
        }
        if item.kind == .markdown || ClipboardFormatter.isMarkdown(text) {
            result.append(.markdown)
        }

        if !result.contains(.plain) {
            result.append(.plain)
        }

        // 去重，保持插入顺序。
        var seen = Set<ClipboardTransform>()
        return result.filter { seen.insert($0).inserted }
    }

    init(transforms: [ClipboardTransform]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.shadowOpacity = 0.45
        layer?.shadowRadius = 18
        layer?.shadowOffset = NSSize(width: 0, height: 6)

        visualEffect.material = .menu
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(visualEffect)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(stack)

        let header = NSTextField(labelWithString: "格式化粘贴")
        header.font = .systemFont(ofSize: 11, weight: .heavy)
        header.textColor = NSColor.secondaryLabelColor
        header.backgroundColor = .clear
        header.translatesAutoresizingMaskIntoConstraints = false
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: headerRow.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: headerRow.topAnchor, constant: 4),
            header.bottomAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: -4)
        ])
        stack.addArrangedSubview(headerRow)

        for (index, transform) in transforms.enumerated() {
            let row = FormatRow(transform: transform, shortcut: shortcut(for: index))
            row.onClick = { [weak self] in self?.commit(at: index) }
            row.onHover = { [weak self] in self?.setHighlight(index: index) }
            rows.append(row)
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),

            widthAnchor.constraint(equalToConstant: 240)
        ])

        setHighlight(index: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
            return true
        case 36, 76: // Return
            commit(at: highlightedIndex)
            return true
        case 125: // Down
            setHighlight(index: min(rows.count - 1, highlightedIndex + 1))
            return true
        case 126: // Up
            setHighlight(index: max(0, highlightedIndex - 1))
            return true
        default:
            // 数字键直接选择第 N 项
            if let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), digit >= 1, digit <= rows.count {
                commit(at: digit - 1)
                return true
            }
            return false
        }
    }

    private func setHighlight(index: Int) {
        guard rows.indices.contains(index) else {
            return
        }
        highlightedIndex = index
        for (i, row) in rows.enumerated() {
            row.isHighlighted = (i == index)
        }
    }

    private func commit(at index: Int) {
        guard rows.indices.contains(index) else {
            return
        }
        onPick?(rows[index].transform)
    }

    private func shortcut(for index: Int) -> String {
        guard index < 9 else { return "" }
        return "\(index + 1)"
    }
}

@MainActor
private final class FormatRow: NSView {
    let transform: ClipboardTransform
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?

    var isHighlighted: Bool = false {
        didSet {
            applyStyle()
        }
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(transform: ClipboardTransform, shortcut: String) {
        self.transform = transform
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let badgeText: String
        switch transform {
        case .original: badgeText = "≡"
        case .json:     badgeText = "{}"
        case .xml:      badgeText = "<>"
        case .yaml:     badgeText = "yml"
        case .sql:      badgeText = "sql"
        case .markdown: badgeText = "md"
        case .plain:    badgeText = "T"
        }

        badgeLabel.stringValue = badgeText
        badgeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .heavy)
        badgeLabel.textColor = NSColor.secondaryLabelColor
        badgeLabel.alignment = .center
        badgeLabel.backgroundColor = .clear
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)

        titleLabel.stringValue = transform.displayName
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor.labelColor
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        shortcutLabel.stringValue = shortcut
        shortcutLabel.font = .systemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = NSColor.tertiaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.backgroundColor = .clear
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shortcutLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            badgeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeLabel.widthAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    private func applyStyle() {
        layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.clear.cgColor
        titleLabel.textColor = isHighlighted ? NSColor.white : NSColor.labelColor
        badgeLabel.textColor = isHighlighted
            ? NSColor.white.withAlphaComponent(0.85)
            : NSColor.secondaryLabelColor
        shortcutLabel.textColor = isHighlighted
            ? NSColor.white.withAlphaComponent(0.78)
            : NSColor.tertiaryLabelColor
    }
}
