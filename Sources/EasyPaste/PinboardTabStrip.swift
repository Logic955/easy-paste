import AppKit
import EasyPasteCore

/// 顶部 Pinboard tab 条：[All] [Pinned] [<user boards>] [+]
@MainActor
final class PinboardTabStrip: NSView {
    var onSelect: ((BoardSelector) -> Void)?
    var onCreate: (() -> Void)?
    var onContextMenu: ((BoardSelector, NSEvent) -> Void)?

    private let scrollView = NSScrollView()
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(boards: [BoardSelector], names: [BoardSelector: String], active: BoardSelector) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for board in boards {
            let pill = TabPill(
                title: names[board] ?? "Pinboard",
                isActive: board == active,
                isBuiltin: board == .all || board == .pinned
            )
            pill.onClick = { [weak self] in self?.onSelect?(board) }
            pill.onContextMenu = { [weak self] event in self?.onContextMenu?(board, event) }
            stack.addArrangedSubview(pill)
        }

        let plus = TabPill(title: "+", isActive: false, isBuiltin: true, isPlus: true)
        plus.onClick = { [weak self] in self?.onCreate?() }
        stack.addArrangedSubview(plus)
    }

    func applyTheme(_ theme: EasyPasteTheme = EasyPasteThemeStore.effectiveTheme) {
        for case let pill as TabPill in stack.arrangedSubviews {
            pill.applyTheme(theme)
        }
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        scrollView.documentView = document
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            document.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.widthAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -4),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: document.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
}

@MainActor
private final class TabPill: NSView {
    var onClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let isBuiltin: Bool
    private let isActive: Bool
    private let isPlus: Bool
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet { applyStyle() }
    }

    init(title: String, isActive: Bool, isBuiltin: Bool, isPlus: Bool = false) {
        self.isActive = isActive
        self.isBuiltin = isBuiltin
        self.isPlus = isPlus
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.borderWidth = 0.5
        layer?.borderColor = EasyPasteThemeStore.effectiveTheme.pillBorder.withAlphaComponent(isActive ? 0.9 : 0.55).cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: isActive ? .bold : .semibold)
        titleLabel.alignment = .center
        titleLabel.backgroundColor = .clear
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isPlus ? 10 : 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: isPlus ? -10 : -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyStyle()
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

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        if !isBuiltin {
            onContextMenu?(event)
        }
    }

    func applyTheme(_ theme: EasyPasteTheme = EasyPasteThemeStore.effectiveTheme) {
        layer?.borderColor = theme.pillBorder.withAlphaComponent(isActive ? 0.9 : 0.55).cgColor
        applyStyle()
    }

    private func applyStyle() {
        let theme = EasyPasteThemeStore.effectiveTheme
        let base = theme.toolbarButtonBackgroundBase
        // 平滑过渡，避免闪烁
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if isActive {
            // 激活态：更亮、更白，有微阴影衬出来
            layer?.backgroundColor = base.withAlphaComponent(theme.isDark ? 0.26 : 0.10).cgColor
            titleLabel.textColor = theme.pillText
        } else if isPlus {
            layer?.backgroundColor = base.withAlphaComponent(isHovering ? 0.12 : 0.05).cgColor
            titleLabel.textColor = theme.secondaryText
        } else {
            layer?.backgroundColor = base.withAlphaComponent(isHovering ? 0.14 : 0.07).cgColor
            titleLabel.textColor = isHovering ? theme.primaryText : theme.secondaryText
        }
        CATransaction.commit()
    }
}
