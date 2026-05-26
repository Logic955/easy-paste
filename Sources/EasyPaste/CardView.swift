import AppKit
import ImageIO
import EasyPasteCore

/// 卡片尺寸/字号按一个 scale 因子统一缩放，避免在不同分辨率屏幕上比例失调。
@MainActor
struct CardMetrics {
    let scale: CGFloat
    var cardWidth: CGFloat { round(228 * scale) }
    var cardHeight: CGFloat { round(216 * scale) }
    var cornerRadius: CGFloat { round(12 * scale) }
    var headerHeight: CGFloat { round(46 * scale) }
    var footerHeight: CGFloat { round(25 * scale) }
    /// footer 内文字距离顶部分割线的留白
    var footerTopPad: CGFloat { round(6 * scale) }
    var hPad: CGFloat { round(12 * scale) }
    var badgeSize: CGFloat { headerHeight }
    var badgeIconBleed: CGFloat { round(7 * scale) }
    var badgeRadius: CGFloat { round(10 * scale) }
    var typeFontSize: CGFloat { 13 * scale }
    var timeFontSize: CGFloat { 11 * scale }
    var pinFontSize: CGFloat { 13 * scale }
    var badgeFontSize: CGFloat { 17 * scale }
    var bodyFontSize: CGFloat { 12 * scale }
    var footerFontSize: CGFloat { 11 * scale }
    var bodyTopPad: CGFloat { round(10 * scale) }
}

/// 全局缺省值（在 PanelController 设置实际 scale 之前用）。
@MainActor
enum CardLayout {
    nonisolated(unsafe) static var current: CardMetrics = CardMetrics(scale: 1.0)
    static var cardWidth: CGFloat { current.cardWidth }
    static var cardHeight: CGFloat { current.cardHeight }
    static var cornerRadius: CGFloat { current.cornerRadius }
    static var headerHeight: CGFloat { current.headerHeight }
    static var footerHeight: CGFloat { current.footerHeight }
}

@MainActor
struct CardShortcutHint: Equatable {
    var commandNumber: Int?
    var showsPlainText: Bool

    static let none = CardShortcutHint(commandNumber: nil, showsPlainText: false)
}

@MainActor
enum ClipCardRenderMode {
    case lightweight
    case hydrated
}

@MainActor
struct ClipCardHydrationPayload {
    var icon: NSImage?
    var headerColor: NSColor?
    var image: NSImage?
    var richPreview: NSAttributedString?
}

@MainActor
final class ClipCardView: NSView {
    let itemID: UUID
    var onSelect: ((UUID, Bool, NSEvent.ModifierFlags) -> Void)?
    var onContextMenu: ((UUID, NSEvent) -> Void)?

    var isSelected = false {
        didSet { updateSelection() }
    }

    var shortcutHint: CardShortcutHint = .none {
        didSet { updateShortcutHint() }
    }

    private let item: ClipboardItem
    private let metrics: CardMetrics
    private let renderMode: ClipCardRenderMode
    private let header = NSView()
    private let selectionRing = NSView()
    private let clickOverlay = CardClickOverlay()
    private weak var headerGradient: CAGradientLayer?
    private weak var bodyGradient: CAGradientLayer?
    private weak var badgeIconView: NSImageView?
    private weak var imagePreviewView: NSImageView?
    private weak var textPreviewField: NSTextField?
    private let pinIcon = NSTextField(labelWithString: "★")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private lazy var sourceAppIcon: NSImage? = loadSourceAppIcon()
    private var hydrationTask: Task<Void, Never>?
    private var trackingArea: NSTrackingArea?
    private var isMouseDownInside = false
    private var wasSelectedOnMouseDown = false
    private static var sourceIconCache: [String: NSImage] = [:]
    private static var missingSourceIconBundleIDs: Set<String> = []
    private static var loadingSourceIconBundleIDs: Set<String> = []
    private static var trimmedIconCache: [String: NSImage] = [:]
    private static var headerColorCache: [String: NSColor] = [:]
    private static let sourceIconLoadQueue = DispatchQueue(label: "com.easypaste.card-icon-load", qos: .utility)
    private var isHovering = false {
        didSet { updateSelection() }
    }

    init(
        item: ClipboardItem,
        metrics: CardMetrics = CardLayout.current,
        renderMode: ClipCardRenderMode = .hydrated
    ) {
        self.item = item
        self.metrics = metrics
        self.renderMode = renderMode
        itemID = item.id
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func handleMouseDown(with event: NSEvent) {
        isMouseDownInside = true
        wasSelectedOnMouseDown = isSelected
        onSelect?(itemID, false, event.modifierFlags)
    }

    private func handleMouseUp(with event: NSEvent) {
        let clickedInside = isMouseDownInside && bounds.contains(convert(event.locationInWindow, from: nil))
        let shouldPaste = clickedInside && (wasSelectedOnMouseDown || event.modifierFlags.contains(.shift))
        isMouseDownInside = false
        if shouldPaste {
            onSelect?(itemID, true, event.modifierFlags)
        }
        wasSelectedOnMouseDown = false
    }

    private func handleRightMouseDown(with event: NSEvent) {
        isMouseDownInside = false
        wasSelectedOnMouseDown = false
        onSelect?(itemID, false, event.modifierFlags)
        onContextMenu?(itemID, event)
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

    override func layout() {
        super.layout()
        // header 渐变层手动跟随 header frame
        if let g = headerGradient {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            g.frame = header.bounds
            CATransaction.commit()
        }
        if let g = bodyGradient, let superlayer = g.superlayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            g.frame = superlayer.bounds
            CATransaction.commit()
        }
        // 卡片保持贴合面板，不做浮动阴影。
        if let layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.shadowPath = nil
            CATransaction.commit()
        }
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: metrics.cardWidth).isActive = true
        heightAnchor.constraint(equalToConstant: metrics.cardHeight).isActive = true
        wantsLayer = true
        layer?.cornerRadius = metrics.cornerRadius
        layer?.masksToBounds = false
        layer?.backgroundColor = EasyPasteThemeStore.effectiveTheme.cardBackground.cgColor
        layer?.borderWidth = 0
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.shadowOffset = .zero

        // 内层用一个圆角 clip view 收纳上下两块，避免 header 圆角和 layer.shadow 冲突。
        let clip = NSView()
        clip.wantsLayer = true
        clip.layer?.cornerRadius = metrics.cornerRadius
        clip.layer?.masksToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)

        header.wantsLayer = true
        header.layer?.zPosition = 10
        let initialHeaderColor = headerColor(allowsExpensiveLoad: renderMode == .hydrated)
        let gradient = CAGradientLayer()
        gradient.colors = [
            initialHeaderColor.blended(withFraction: 0.06, of: .white)?.cgColor ?? initialHeaderColor.cgColor,
            initialHeaderColor.cgColor
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.zPosition = 0
        gradient.frame = .zero
        header.layer?.addSublayer(gradient)
        header.layer?.backgroundColor = initialHeaderColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(header)
        // 把 gradient 引用存起来，在 layout 后更新它的 frame
        self.headerGradient = gradient

        let headerBottomLine = NSView()
        headerBottomLine.wantsLayer = true
        headerBottomLine.layer?.backgroundColor = NSColor.black.withAlphaComponent(EasyPasteThemeStore.effectiveTheme.isDark ? 0.20 : 0.12).cgColor
        headerBottomLine.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(headerBottomLine)

        let typeLabel = NSTextField(labelWithString: headerTitle)
        typeLabel.font = .systemFont(ofSize: metrics.typeFontSize, weight: .bold)
        typeLabel.textColor = .white
        typeLabel.backgroundColor = .clear
        typeLabel.lineBreakMode = .byTruncatingTail
        typeLabel.wantsLayer = true
        typeLabel.layer?.zPosition = 20
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(typeLabel)

        let timeLabel = NSTextField(labelWithString: headerSubtitle)
        timeLabel.font = .systemFont(ofSize: metrics.timeFontSize, weight: .semibold)
        timeLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        timeLabel.backgroundColor = .clear
        timeLabel.lineBreakMode = .byTruncatingTail
        timeLabel.wantsLayer = true
        timeLabel.layer?.zPosition = 20
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(timeLabel)

        let badge = makeBadge()
        badge.layer?.zPosition = 20
        header.addSubview(badge)

        pinIcon.font = .systemFont(ofSize: metrics.pinFontSize, weight: .bold)
        pinIcon.textColor = NSColor.systemYellow
        pinIcon.backgroundColor = .clear
        pinIcon.alignment = .center
        pinIcon.isHidden = !item.pinned
        pinIcon.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(pinIcon)

        // body
        let body = makeBody()
        body.wantsLayer = true
        body.layer?.zPosition = 1
        clip.addSubview(body)

        // footer
        let footer: NSView
        if item.kind == .image {
            let info = imageInfoParts(allowsExpensiveLoad: renderMode == .hydrated)
            footer = ImageInfoFooterView(dimensions: info.dimensions, size: info.size, metrics: metrics)
        } else {
            let label = NSTextField(labelWithString: footerText)
            label.font = .systemFont(ofSize: metrics.footerFontSize, weight: .medium)
            label.textColor = EasyPasteThemeStore.effectiveTheme.footerText
            label.backgroundColor = .clear
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            footer = label
        }
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        footer.layer?.zPosition = 5
        clip.addSubview(footer)

        shortcutLabel.font = .systemFont(ofSize: metrics.footerFontSize + 1, weight: .semibold)
        shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.52)
        shortcutLabel.backgroundColor = .clear
        shortcutLabel.alignment = .right
        shortcutLabel.isHidden = true
        shortcutLabel.alphaValue = 0
        shortcutLabel.wantsLayer = true
        shortcutLabel.layer?.zPosition = 30
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(shortcutLabel)

        selectionRing.wantsLayer = true
        selectionRing.layer?.cornerRadius = metrics.cornerRadius
        selectionRing.layer?.borderWidth = 0
        selectionRing.layer?.borderColor = NSColor.controlAccentColor.cgColor
        selectionRing.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionRing)

        clickOverlay.translatesAutoresizingMaskIntoConstraints = false
        clickOverlay.onMouseDown = { [weak self] event in
            self?.handleMouseDown(with: event)
        }
        clickOverlay.onMouseUp = { [weak self] event in
            self?.handleMouseUp(with: event)
        }
        clickOverlay.onRightMouseDown = { [weak self] event in
            self?.handleRightMouseDown(with: event)
        }
        addSubview(clickOverlay)

        let h = metrics.hPad

        NSLayoutConstraint.activate([
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),

            header.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            header.topAnchor.constraint(equalTo: clip.topAnchor),
            header.heightAnchor.constraint(equalToConstant: metrics.headerHeight),

            headerBottomLine.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            headerBottomLine.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            headerBottomLine.topAnchor.constraint(equalTo: header.bottomAnchor),
            headerBottomLine.heightAnchor.constraint(equalToConstant: 1),

            typeLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: h),
            typeLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 9 * metrics.scale),
            typeLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8 * metrics.scale),

            timeLabel.leadingAnchor.constraint(equalTo: typeLabel.leadingAnchor),
            timeLabel.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 1),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -8 * metrics.scale),

            badge.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            badge.topAnchor.constraint(equalTo: header.topAnchor),
            badge.widthAnchor.constraint(equalToConstant: metrics.badgeSize),
            badge.heightAnchor.constraint(equalToConstant: metrics.badgeSize),

            pinIcon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            pinIcon.topAnchor.constraint(equalTo: header.topAnchor, constant: 6),

            body.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            body.topAnchor.constraint(equalTo: header.bottomAnchor),
            body.bottomAnchor.constraint(equalTo: clip.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: h * 0.85),
            footer.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -h * 0.85),
            footer.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -metrics.footerTopPad),

            shortcutLabel.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -10 * metrics.scale),
            shortcutLabel.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -metrics.footerTopPad),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 12 * metrics.scale),

            selectionRing.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectionRing.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectionRing.topAnchor.constraint(equalTo: topAnchor),
            selectionRing.bottomAnchor.constraint(equalTo: bottomAnchor),

            clickOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            clickOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            clickOverlay.topAnchor.constraint(equalTo: topAnchor),
            clickOverlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateSelection()
        updateShortcutHint()
    }

    private func makeBadge() -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = metrics.badgeRadius
        badge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
        badge.layer?.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = displayAppIcon(allowsExpensiveLoad: renderMode == .hydrated) ?? fallbackIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        badgeIconView = icon
        badge.addSubview(icon)

        let bleed = metrics.badgeIconBleed
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -bleed),
            icon.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: bleed),
            icon.topAnchor.constraint(equalTo: badge.topAnchor, constant: -bleed),
            icon.bottomAnchor.constraint(equalTo: badge.bottomAnchor, constant: bleed)
        ])
        return badge
    }

    private func makeBody() -> NSView {
        let h = metrics.hPad
        if item.kind == .image {
            let image: NSImage?
            if renderMode == .hydrated,
               let data = imagePNGData {
                image = NSImage(data: data)
            } else {
                image = nil
            }
            return makeImageBody(image: image, horizontalPadding: h)
        }

        // 用 attributedString 精细控制行距 + 字间距，让多行预览读起来更舒展。
        // 结构化文本（json/xml/yaml/sql/code/markdown/url）用等宽字体，更专业。
        let useMono: Bool = {
            switch item.kind {
            case .json, .xml, .yaml, .sql, .code, .markdown, .url: return true
            default: return false
            }
        }()
        let bodyFont: NSFont = useMono
            ? .monospacedSystemFont(ofSize: metrics.bodyFontSize, weight: .regular)
            : .systemFont(ofSize: metrics.bodyFontSize, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = round(2.4 * metrics.scale)
        para.lineBreakMode = .byCharWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: EasyPasteThemeStore.effectiveTheme.primaryText.withAlphaComponent(0.92),
            .paragraphStyle: para,
            .kern: useMono ? 0 : 0.05
        ]
        let plainPreview = Self.clippedPreview(previewSourceText, limit: 520)
        let preview = NSTextField(labelWithString: "")
        let richPreview = renderMode == .hydrated ? richPreviewText : nil
        preview.attributedStringValue = richPreview
            ?? syntaxHighlightedPreview(
                plainPreview,
                baseAttributes: attrs,
                baseFont: bodyFont,
                paragraphStyle: para
            )
        preview.backgroundColor = .clear
        preview.lineBreakMode = .byCharWrapping
        preview.maximumNumberOfLines = 0
        preview.cell?.wraps = true
        preview.cell?.isScrollable = false
        preview.cell?.usesSingleLineMode = false
        preview.cell?.lineBreakMode = .byCharWrapping
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.translatesAutoresizingMaskIntoConstraints = false
        textPreviewField = preview

        let container = NSView()
        container.wantsLayer = true
        let bodyColor = EasyPasteThemeStore.effectiveTheme.cardBodyBackground
        container.layer?.backgroundColor = bodyColor.cgColor
        container.layer?.masksToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        if let layer = container.layer {
            let gradient = CAGradientLayer()
            gradient.colors = cardBodyGradientColors(base: bodyColor)
            gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.zPosition = 0
            layer.addSublayer(gradient)
            bodyGradient = gradient
        }
        container.addSubview(preview)
        preview.wantsLayer = true
        preview.layer?.zPosition = 10

        let bottomFade = BottomFadeView(
            color: bodyColor,
            metrics: metrics
        )
        bottomFade.wantsLayer = true
        bottomFade.layer?.zPosition = 20
        bottomFade.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomFade)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: container.topAnchor, constant: metrics.bodyTopPad),
            preview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: h),
            preview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -h),
            preview.bottomAnchor.constraint(lessThanOrEqualTo: bottomFade.topAnchor, constant: -2 * metrics.scale),
            preview.heightAnchor.constraint(lessThanOrEqualToConstant: max(
                44,
                metrics.cardHeight - metrics.headerHeight - metrics.footerHeight - metrics.bodyTopPad - 10 * metrics.scale
            )),

            bottomFade.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomFade.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomFade.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomFade.heightAnchor.constraint(equalToConstant: round(34 * metrics.scale))
        ])
        return container
    }

    private func makeImageBody(image: NSImage?, horizontalPadding h: CGFloat) -> NSView {
        let imageView = NSImageView()
        imageView.image = image ?? placeholderImage
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = EasyPasteThemeStore.effectiveTheme.secondaryText.withAlphaComponent(0.52)
        imageView.alphaValue = image == nil ? 0.62 : 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imagePreviewView = imageView

        let imageStage = CheckerboardView(squareSize: max(8, round(8 * metrics.scale)))
        imageStage.wantsLayer = true
        imageStage.layer?.cornerRadius = 5 * metrics.scale
        imageStage.layer?.masksToBounds = true
        imageStage.translatesAutoresizingMaskIntoConstraints = false
        imageStage.addSubview(imageView)

        let body = NSView()
        body.wantsLayer = true
        body.layer?.backgroundColor = EasyPasteThemeStore.effectiveTheme.cardBodyBackground.cgColor
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(imageStage)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageStage.leadingAnchor, constant: h * 0.35),
            imageView.trailingAnchor.constraint(equalTo: imageStage.trailingAnchor, constant: -h * 0.35),
            imageView.topAnchor.constraint(equalTo: imageStage.topAnchor, constant: h * 0.35),
            imageView.bottomAnchor.constraint(equalTo: imageStage.bottomAnchor, constant: -h * 0.35),

            imageStage.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: h),
            imageStage.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -h),
            imageStage.topAnchor.constraint(equalTo: body.topAnchor, constant: metrics.bodyTopPad),
            imageStage.bottomAnchor.constraint(equalTo: body.bottomAnchor, constant: -metrics.bodyTopPad)
        ])
        return body
    }

    private func cardBodyGradientColors(base: NSColor) -> [CGColor] {
        let theme = EasyPasteThemeStore.effectiveTheme
        guard theme.isDark else {
            return [
                base.cgColor,
                base.blended(withFraction: 0.035, of: .black)?.cgColor ?? base.cgColor
            ]
        }
        let top = NSColor(calibratedRed: 0.092, green: 0.102, blue: 0.118, alpha: 0.99)
        let bottom = NSColor(calibratedRed: 0.058, green: 0.065, blue: 0.076, alpha: 0.99)
        return [top.cgColor, base.cgColor, bottom.cgColor]
    }

    private func updateSelection() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowOpacity = 0
        layer?.shadowRadius = 0
        layer?.shadowOffset = .zero
        layer?.shadowPath = nil
        selectionRing.layer?.borderWidth = isSelected ? 3.0 : (isHovering ? 1.0 : 0.0)
        let hoverColor = EasyPasteThemeStore.effectiveTheme.isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.12)
        selectionRing.layer?.borderColor = (isSelected
            ? NSColor.controlAccentColor
            : hoverColor
        ).cgColor
        layer?.setAffineTransform(.identity)
        CATransaction.commit()
    }

    private func updateShortcutHint() {
        var parts: [String] = []
        if let number = shortcutHint.commandNumber {
            parts.append("\(number)")
        }
        if shortcutHint.showsPlainText {
            parts.append("≡")
        }
        let text = parts.joined(separator: "  ")

        shortcutLabel.stringValue = text
        let visible = !text.isEmpty
        if visible {
            shortcutLabel.isHidden = false
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            shortcutLabel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak shortcutLabel] in
            Task { @MainActor in
                if !visible {
                    shortcutLabel?.isHidden = true
                }
            }
        }
    }

    func hydrateAsync(priorityIndex: Int) {
        guard renderMode == .lightweight, hydrationTask == nil else { return }
        let cardID = itemID
        hydrationTask = Task { @MainActor [weak self] in
            let delayMS = 45 + min(priorityIndex, 12) * 28
            try? await Task.sleep(nanoseconds: UInt64(delayMS) * 1_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.itemID == cardID,
                  self.window?.isVisible == true else {
                return
            }
            let start = EasyPasteDiagnostics.now()
            self.applyHydration()
            EasyPasteDiagnostics.log("panel.card.hydrate", [
                "kind": self.item.kind.rawValue,
                "ms": EasyPasteDiagnostics.elapsedMS(since: start)
            ])
        }
    }

    private func applyHydration() {
        let payload = ClipCardHydrationPayload(
            icon: displayAppIcon(allowsExpensiveLoad: false),
            headerColor: headerColor(allowsExpensiveLoad: false),
            image: hydratedPreviewImage(),
            richPreview: item.kind == .image ? nil : richPreviewText
        )
        hydrateSourceIconAsync()

        if let headerColor = payload.headerColor {
            applyHeaderColor(headerColor)
        }

        if let icon = payload.icon {
            badgeIconView?.image = icon
        }

        if let image = payload.image, item.kind == .image {
            imagePreviewView?.image = image
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.allowsImplicitAnimation = true
                imagePreviewView?.animator().alphaValue = 1
            }
        } else if let richPreview = payload.richPreview {
            textPreviewField?.attributedStringValue = richPreview
        }
    }

    private func hydrateSourceIconAsync() {
        guard let bundleID = item.sourceBundleID else { return }
        if Self.sourceIconCache[bundleID] != nil || Self.loadingSourceIconBundleIDs.contains(bundleID) {
            return
        }
        if Self.missingSourceIconBundleIDs.contains(bundleID) {
            return
        }

        Self.loadingSourceIconBundleIDs.insert(bundleID)
        let cardID = itemID
        Self.sourceIconLoadQueue.async { [bundleID] in
            let iconData: Data?
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                iconData = NSWorkspace.shared.icon(forFile: appURL.path).tiffRepresentation
            } else {
                iconData = nil
            }

            Task { @MainActor [weak self] in
                Self.loadingSourceIconBundleIDs.remove(bundleID)
                guard let iconData,
                      let icon = NSImage(data: iconData) else {
                    Self.missingSourceIconBundleIDs.insert(bundleID)
                    return
                }

                Self.sourceIconCache[bundleID] = icon
                guard let self,
                      self.itemID == cardID,
                      self.window?.isVisible == true else {
                    return
                }

                if let displayIcon = self.displayAppIcon(allowsExpensiveLoad: true) {
                    self.badgeIconView?.image = displayIcon
                }
                self.applyHeaderColor(self.headerColor(allowsExpensiveLoad: true))
            }
        }
    }

    private func applyHeaderColor(_ color: NSColor) {
        header.layer?.backgroundColor = color.cgColor
        headerGradient?.colors = [
            color.blended(withFraction: 0.06, of: .white)?.cgColor ?? color.cgColor,
            color.cgColor
        ]
    }

    private func hydratedPreviewImage() -> NSImage? {
        guard item.kind == .image,
              let data = imagePNGData else {
            return nil
        }
        return NSImage(data: data)
    }

    private var placeholderImage: NSImage? {
        let image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        return image?.withSymbolConfiguration(.init(pointSize: metrics.badgeFontSize + 6, weight: .medium))
    }

    private func headerColor(allowsExpensiveLoad: Bool) -> NSColor {
        if let bundleID = item.sourceBundleID,
           let cached = Self.headerColorCache[bundleID] {
            return cached
        }

        let fallback = NSColor(calibratedRed: 0.17, green: 0.58, blue: 0.91, alpha: 1.0)
        guard allowsExpensiveLoad else {
            return fallback
        }

        let color = sourceAppIcon?.dominantHeaderColor()
            ?? fallback
        if let bundleID = item.sourceBundleID {
            Self.headerColorCache[bundleID] = color
        }
        return color
    }

    private var kindLabel: String {
        switch item.kind {
        case .text:     return "Text"
        case .url:      return "URL"
        case .json:     return "JSON"
        case .xml:      return "XML"
        case .yaml:     return "YAML"
        case .sql:      return "SQL"
        case .markdown: return "Markdown"
        case .code:     return "Code"
        case .image:    return "Image"
        }
    }

    private var headerTitle: String {
        item.kind == .image ? "Image" : kindLabel
    }

    private var headerSubtitle: String {
        let time = relativeTime(from: item.updatedAt)
        if item.kind == .image, let imageName = item.imageName?.split(separator: " ").first {
            let stem = URL(fileURLWithPath: String(imageName)).deletingPathExtension().lastPathComponent
            if !stem.isEmpty {
                return "\(time) · \(stem)"
            }
        }
        return time
    }

    private func appIcon(allowsExpensiveLoad: Bool) -> NSImage? {
        guard allowsExpensiveLoad else {
            return cachedSourceAppIcon
        }
        return sourceAppIcon
    }

    private var cachedSourceAppIcon: NSImage? {
        guard let bundleID = item.sourceBundleID else { return nil }
        return Self.sourceIconCache[bundleID]
    }

    private func displayAppIcon(allowsExpensiveLoad: Bool) -> NSImage? {
        guard let icon = appIcon(allowsExpensiveLoad: allowsExpensiveLoad) else { return nil }
        guard let bundleID = item.sourceBundleID else {
            guard allowsExpensiveLoad else { return icon }
            return icon.trimmingTransparentPixels() ?? icon
        }
        if let cached = Self.trimmedIconCache[bundleID] {
            return cached
        }
        guard allowsExpensiveLoad else { return icon }
        let trimmed = icon.trimmingTransparentPixels() ?? icon
        Self.trimmedIconCache[bundleID] = trimmed
        return trimmed
    }

    private func loadSourceAppIcon() -> NSImage? {
        guard let bundleID = item.sourceBundleID else {
            return nil
        }
        if let cached = Self.sourceIconCache[bundleID] {
            return cached
        }
        if Self.missingSourceIconBundleIDs.contains(bundleID) {
            return nil
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Self.missingSourceIconBundleIDs.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        Self.sourceIconCache[bundleID] = icon
        return icon
    }

    private var fallbackIcon: NSImage? {
        let symbol: String
        switch item.kind {
        case .text: symbol = "text.alignleft"
        case .url: symbol = "link"
        case .json, .xml, .yaml, .sql, .markdown, .code: symbol = "chevron.left.forwardslash.chevron.right"
        case .image: symbol = "photo"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return image?.withSymbolConfiguration(.init(pointSize: metrics.badgeFontSize, weight: .semibold))
    }

    private var imageInfoText: String {
        let parts = imageInfoParts(allowsExpensiveLoad: renderMode == .hydrated)
        guard let size = parts.size else { return parts.dimensions }
        return "\(parts.dimensions)  ·  \(size)"
    }

    private func imageInfoParts(allowsExpensiveLoad: Bool) -> (dimensions: String, size: String?) {
        guard allowsExpensiveLoad else {
            if let count = item.imageByteCount {
                return (normalizedPreviewDimensions, Self.formattedByteCount(count))
            }
            return (normalizedPreviewDimensions, nil)
        }
        guard let data = imagePNGData else {
            if let count = item.imageByteCount {
                return (normalizedPreviewDimensions, Self.formattedByteCount(count))
            }
            return (normalizedPreviewDimensions, nil)
        }
        let dimensions = Self.pixelDimensions(from: data) ?? normalizedPreviewDimensions
        return (dimensions, Self.formattedByteCount(data.count))
    }

    private var characterCountText: String {
        let count = item.text?.count ?? item.preview.count
        return "\(Self.groupedNumber(count)) character\(count == 1 ? "" : "s")"
    }

    private var footerText: String {
        if item.kind == .image {
            return imageInfoText
        }
        return characterCountText
    }

    private var previewText: String {
        if !item.preview.isEmpty {
            return item.preview
        }
        return item.text ?? ""
    }

    private var previewSourceText: String {
        guard let text = item.text, !text.isEmpty else {
            return previewText
        }
        return text
    }

    private var richPreviewText: NSAttributedString? {
        let data: Data?
        let options: [NSAttributedString.DocumentReadingOptionKey: Any]
        if let rtfBase64 = item.rtfDataBase64,
           let rtfData = Data(base64Encoded: rtfBase64) {
            data = rtfData
            options = [.documentType: NSAttributedString.DocumentType.rtf]
        } else if let rtfData = payloadData(relativePath: item.rtfBlobPath) {
            data = rtfData
            options = [.documentType: NSAttributedString.DocumentType.rtf]
        } else {
            return nil
        }

        guard let data,
              data.count <= 48_000,
              let attributed = try? NSMutableAttributedString(data: data, options: options, documentAttributes: nil),
              attributed.length > 0 else {
            return nil
        }

        let maxLength = min(attributed.length, 520)
        let preview = attributed.attributedSubstring(from: NSRange(location: 0, length: maxLength)).mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString(string: attributed.string)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = round(2.4 * metrics.scale)
        paragraph.lineBreakMode = .byCharWrapping
        sanitizeRichPreview(preview, paragraph: paragraph)
        return preview
    }

    private var imagePNGData: Data? {
        if let base64 = item.imagePNGBase64,
           let data = Data(base64Encoded: base64) {
            return data
        }
        return payloadData(relativePath: item.imageBlobPath)
    }

    private func payloadData(relativePath: String?) -> Data? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EasyPaste", isDirectory: true)
        return try? Data(contentsOf: support.appendingPathComponent(relativePath))
    }

    private func sanitizeRichPreview(_ preview: NSMutableAttributedString, paragraph: NSParagraphStyle) {
        let fullRange = NSRange(location: 0, length: preview.length)
        guard preview.length > 0 else { return }

        let theme = EasyPasteThemeStore.effectiveTheme
        preview.removeAttribute(.backgroundColor, range: fullRange)
        preview.removeAttribute(.underlineStyle, range: fullRange)
        preview.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)

        let defaultFont = NSFont.systemFont(ofSize: metrics.bodyFontSize, weight: .regular)
        let defaultColor = theme.primaryText.withAlphaComponent(0.92)
        preview.enumerateAttributes(in: fullRange) { attrs, range, _ in
            let normalizedFont = (attrs[.font] as? NSFont)
                .map { normalizedPreviewFont($0) }
                ?? defaultFont
            preview.addAttribute(.font, value: normalizedFont, range: range)
            guard let color = attrs[.foregroundColor] as? NSColor else {
                preview.addAttribute(.foregroundColor, value: defaultColor, range: range)
                return
            }
            preview.addAttribute(.foregroundColor, value: normalizedPreviewColor(color), range: range)
        }
    }

    private func normalizedPreviewFont(_ source: NSFont) -> NSFont {
        let traits = NSFontManager.shared.traits(of: source)
        let weight: NSFont.Weight = traits.contains(.boldFontMask) ? .semibold : .regular
        let base = NSFont.systemFont(ofSize: metrics.bodyFontSize, weight: weight)
        guard traits.contains(.italicFontMask) else {
            return base
        }
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }

    private func normalizedPreviewColor(_ color: NSColor) -> NSColor {
        let theme = EasyPasteThemeStore.effectiveTheme
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return theme.primaryText.withAlphaComponent(0.92)
        }
        let brightness = (0.299 * rgb.redComponent) + (0.587 * rgb.greenComponent) + (0.114 * rgb.blueComponent)
        if theme.isDark {
            if brightness > 0.88 {
                return theme.primaryText.withAlphaComponent(0.94)
            }
            if brightness < 0.20 {
                return theme.primaryText.withAlphaComponent(0.84)
            }
            return softenedPreviewColor(rgb, dark: true)
        }
        if brightness < 0.16 {
            return theme.primaryText.withAlphaComponent(0.92)
        }
        if brightness > 0.92 {
            return theme.secondaryText.withAlphaComponent(0.72)
        }
        return softenedPreviewColor(rgb, dark: false)
    }

    private func softenedPreviewColor(_ color: NSColor, dark: Bool) -> NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.08 {
            if dark {
                let readableGray = min(max(brightness, 0.68), 0.88)
                return NSColor(calibratedWhite: readableGray, alpha: 0.90)
            }
            return color.withAlphaComponent(0.82)
        }
        let nextSaturation = min(saturation, dark ? 0.54 : 0.48)
        let nextBrightness = dark
            ? min(max(brightness, 0.62), 0.86)
            : min(max(brightness, 0.34), 0.66)
        return NSColor(
            calibratedHue: hue,
            saturation: nextSaturation,
            brightness: nextBrightness,
            alpha: dark ? 0.90 : 0.86
        )
    }

    private func syntaxHighlightedPreview(
        _ text: String,
        baseAttributes: [NSAttributedString.Key: Any],
        baseFont: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes)
        let fullRange = NSRange(location: 0, length: result.length)
        guard result.length > 0 else { return result }

        let theme = EasyPasteThemeStore.effectiveTheme
        let blue = paletteColor(dark: (0.47, 0.68, 0.92), light: (0.18, 0.39, 0.66))
        let purple = paletteColor(dark: (0.73, 0.60, 0.89), light: (0.44, 0.31, 0.66))
        let green = paletteColor(dark: (0.55, 0.76, 0.58), light: (0.25, 0.48, 0.30))
        let orange = paletteColor(dark: (0.82, 0.65, 0.43), light: (0.60, 0.38, 0.16))
        let red = paletteColor(dark: (0.86, 0.52, 0.57), light: (0.64, 0.25, 0.30))
        let muted = theme.secondaryText.withAlphaComponent(theme.isDark ? 0.84 : 0.68)

        func apply(_ pattern: String, color: NSColor, options: NSRegularExpression.Options = []) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.matches(in: text, range: fullRange).forEach { match in
                result.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }

        switch item.kind {
        case .url:
            result.addAttribute(.foregroundColor, value: blue, range: fullRange)
        case .json:
            apply(#""(?:\\.|[^"\\])*"(?=\s*:)"#, color: blue)
            apply(#":\s*"(?:\\.|[^"\\])*""#, color: green)
            apply(#"\b(true|false|null)\b"#, color: purple)
            apply(#"(?<![\w.])-?\b\d+(?:\.\d+)?\b"#, color: orange)
            apply(#"[{}\[\],:]"#, color: muted)
        case .xml:
            apply(#"</?[\w:.-]+"#, color: blue)
            apply(#"\s[\w:.-]+(?=\=)"#, color: purple)
            apply(#""[^"]*"|'[^']*'"#, color: green)
            apply(#"</?|/?>"#, color: muted)
        case .yaml:
            apply(#"(?m)^\s*(?:-\s*)?[\w.-]+(?=\s*:)"#, color: blue)
            apply(#""[^"]*"|'[^']*'"#, color: green)
            apply(#"\b(true|false|null|yes|no)\b"#, color: purple, options: [.caseInsensitive])
            apply(#"(?m)#.*$"#, color: muted)
        case .sql:
            apply(#"\b(SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|AND|OR|GROUP|ORDER|BY|HAVING|LIMIT|OFFSET|INSERT|INTO|VALUES|UPDATE|SET|DELETE|WITH|AS|DISTINCT|COUNT|SUM|AVG|MIN|MAX)\b"#, color: blue, options: [.caseInsensitive])
            apply(#"'(?:''|[^'])*'|"[^"]*""#, color: green)
            apply(#"\b\d+(?:\.\d+)?\b"#, color: orange)
            apply(#"(?m)--.*$"#, color: muted)
        case .markdown:
            apply(#"(?m)^#{1,6}\s+.*$"#, color: blue)
            apply(#"`[^`]+`"#, color: green)
            apply(#"\*\*[^*]+\*\*|__[^_]+__"#, color: purple)
            apply(#"\[[^\]]+\]\([^)]+\)"#, color: blue)
            apply(#"(?m)^>\s+.*$"#, color: muted)
        case .code:
            apply(#"\b(func|function|const|let|var|class|struct|enum|import|export|return|async|await|if|else|for|while|switch|case|guard|try|catch|throw|throws|public|private|final|static)\b"#, color: blue)
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: green)
            apply(#"(?m)//.*$|/\*[\s\S]*?\*/"#, color: muted)
            apply(#"\b\d+(?:\.\d+)?\b"#, color: orange)
        case .text:
            apply(#"https?://[^\s]+"#, color: blue)
            apply(#"\b(TODO|FIXME|NOTE)\b"#, color: red)
        case .image:
            break
        }

        result.addAttribute(.font, value: baseFont, range: fullRange)
        result.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        return result
    }

    private func paletteColor(
        dark: (CGFloat, CGFloat, CGFloat),
        light: (CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        let values = EasyPasteThemeStore.effectiveTheme.isDark ? dark : light
        return NSColor(
            calibratedRed: values.0,
            green: values.1,
            blue: values.2,
            alpha: EasyPasteThemeStore.effectiveTheme.isDark ? 0.92 : 0.88
        )
    }

    private static func clippedPreview(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit)) + "..."
    }

    private static func groupedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static func formattedByteCount(_ bytes: Int) -> String {
        if bytes >= 1_000_000 {
            let value = Double(bytes) / 1_000_000
            return String(format: value >= 10 ? "%.0f MB" : "%.1f MB", value)
        }
        let value = max(1, Int((Double(bytes) / 1_000).rounded(.up)))
        return "\(value) KB"
    }

    private var normalizedPreviewDimensions: String {
        let raw = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = raw.range(of: #"^\s*(\d+)\s*[x×]\s*(\d+)\s*$"#, options: .regularExpression) {
            let parts = raw[match].split(whereSeparator: { $0 == "x" || $0 == "×" })
            if parts.count == 2 {
                let width = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let height = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                return "\(width) × \(height)"
            }
        }
        return raw
    }

    private static func pixelDimensions(from data: Data) -> String? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width > 0,
           height > 0 {
            return "\(width) × \(height)"
        }
        if let rep = NSBitmapImageRep(data: data), rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        guard let image = NSImage(data: data) else { return nil }
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        return "\(width) × \(height)"
    }
}

@MainActor
private final class BottomFadeView: NSView {
    private let color: NSColor
    private let metrics: CardMetrics

    init(color: NSColor, metrics: CardMetrics) {
        self.color = color
        self.metrics = metrics
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let base = color.usingColorSpace(.deviceRGB) ?? color
        let clear = base.withAlphaComponent(0.0).cgColor
        let solid = base.withAlphaComponent(0.98).cgColor
        let locations: [CGFloat] = [0.0, 0.72, 1.0]
        let colors = [
            clear,
            base.withAlphaComponent(0.72).cgColor,
            solid
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else { return }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY + 4 * metrics.scale),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: []
        )
    }
}

@MainActor
private final class ImageInfoFooterView: NSView {
    init(dimensions: String, size: String?, metrics: CardMetrics) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: max(15, round(16 * metrics.scale))).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .gravityAreas
        stack.spacing = 6 * metrics.scale
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        stack.addArrangedSubview(ImageInfoChip(text: dimensions, metrics: metrics))
        if let size {
            stack.addArrangedSubview(ImageInfoChip(text: size, metrics: metrics))
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class ImageInfoChip: NSView {
    init(text: String, metrics: CardMetrics) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = EasyPasteThemeStore.effectiveTheme.imageInfoChipBackground.cgColor
        layer?.cornerRadius = 5 * metrics.scale
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: metrics.footerFontSize, weight: .semibold)
        label.textColor = EasyPasteThemeStore.effectiveTheme.imageInfoText
        label.backgroundColor = .clear
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: max(15, round(16 * metrics.scale))),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6 * metrics.scale),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6 * metrics.scale),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class CardClickOverlay: NSView {
    var onMouseDown: ((NSEvent) -> Void)?
    var onMouseUp: ((NSEvent) -> Void)?
    var onRightMouseDown: ((NSEvent) -> Void)?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(event)
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightMouseDown?(event)
    }
}

@MainActor
private final class CheckerboardView: NSView {
    private let squareSize: CGFloat

    init(squareSize: CGFloat) {
        self.squareSize = squareSize
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = EasyPasteThemeStore.effectiveTheme
        let first = theme.isDark
            ? NSColor(calibratedWhite: 0.10, alpha: 1)
            : NSColor(calibratedWhite: 0.86, alpha: 1)
        let second = theme.isDark
            ? NSColor(calibratedWhite: 0.15, alpha: 1)
            : NSColor(calibratedWhite: 0.92, alpha: 1)
        first.setFill()
        dirtyRect.fill()
        second.setFill()

        let cols = Int(ceil(bounds.width / squareSize))
        let rows = Int(ceil(bounds.height / squareSize))
        for row in 0...rows {
            for col in 0...cols where (row + col).isMultiple(of: 2) {
                NSRect(
                    x: CGFloat(col) * squareSize,
                    y: CGFloat(row) * squareSize,
                    width: squareSize,
                    height: squareSize
                ).fill()
            }
        }
    }
}

@MainActor
final class EmptyClipView: NSView {
    init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // 让外层布局决定宽度（挂在 scrollView 上时会自动撑满 panel 宽度），
        // 这里只保证最小高度，使内部内容有空间居中。
        heightAnchor.constraint(greaterThanOrEqualToConstant: CardLayout.cardHeight).isActive = true

        // 圆形浅色 badge 包一个 SF Symbol，避免单调的两行字。
        let iconWrap = NSView()
        iconWrap.wantsLayer = true
        iconWrap.layer?.cornerRadius = 28
        iconWrap.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        iconWrap.layer?.borderWidth = 0.5
        iconWrap.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        iconWrap.translatesAutoresizingMaskIntoConstraints = false

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
        }
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(iconView)

        let title = NSTextField(labelWithString: "暂无剪贴板内容")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = NSColor.white.withAlphaComponent(0.92)
        title.backgroundColor = .clear

        let hint = NSTextField(labelWithString: message)
        hint.font = .systemFont(ofSize: 12.5, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.55)
        hint.backgroundColor = .clear
        hint.alignment = .center
        hint.maximumNumberOfLines = 2

        let stack = NSStackView(views: [iconWrap, title, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: iconWrap)
        stack.setCustomSpacing(6, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 56),
            iconWrap.heightAnchor.constraint(equalToConstant: 56),
            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

func relativeTime(from date: Date) -> String {
    let seconds = max(0, Int(Date().timeIntervalSince(date)))

    if seconds < 60 {
        return "just now"
    }

    if seconds < 3_600 {
        let m = seconds / 60
        return "\(m) minute\(m == 1 ? "" : "s") ago"
    }

    if seconds < 86_400 {
        let h = seconds / 3_600
        return "\(h) hour\(h == 1 ? "" : "s") ago"
    }

    let d = seconds / 86_400
    return "\(d) day\(d == 1 ? "" : "s") ago"
}

private extension NSImage {
    func dominantHeaderColor(sampleSize: Int = 64) -> NSColor? {
        guard let pixels = renderedRGBAPixels(width: sampleSize, height: sampleSize) else {
            return nil
        }

        let binCount = 24
        var bins = Array(repeating: DominantColorBin(), count: binCount)

        for y in 0..<sampleSize {
            for x in 0..<sampleSize {
                let offset = (y * sampleSize + x) * 4
                let alpha = CGFloat(pixels[offset + 3]) / 255.0
                guard alpha > 0.14 else { continue }

                let red = CGFloat(pixels[offset]) / 255.0 / alpha
                let green = CGFloat(pixels[offset + 1]) / 255.0 / alpha
                let blue = CGFloat(pixels[offset + 2]) / 255.0 / alpha
                let color = NSColor(calibratedRed: min(red, 1), green: min(green, 1), blue: min(blue, 1), alpha: 1)

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

                guard saturation > 0.20, brightness > 0.18 else { continue }
                if saturation < 0.28 && brightness > 0.82 { continue }

                let binIndex = min(binCount - 1, max(0, Int((hue * CGFloat(binCount)).rounded(.down))))
                let weight = alpha * pow(saturation, 1.35) * (0.45 + brightness)
                bins[binIndex].add(red: min(red, 1), green: min(green, 1), blue: min(blue, 1), weight: weight)
            }
        }

        guard let best = bins.max(by: { $0.weight < $1.weight }), best.weight > 1.0 else {
            return nil
        }
        if bins.significantHueGroupCount(relativeTo: best.weight) > 3 {
            return nil
        }

        let color = NSColor(
            calibratedRed: best.red / best.weight,
            green: best.green / best.weight,
            blue: best.blue / best.weight,
            alpha: 1
        )
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        saturation = max(0.52, min(0.86, saturation * 1.08))
        brightness = max(0.66, min(0.88, brightness * 0.98))
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    func trimmingTransparentPixels(alphaThreshold: UInt8 = 8) -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > alphaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return self }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return self }

        let image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        image.isTemplate = isTemplate
        return image
    }

    private func renderedRGBAPixels(width: Int, height: Int) -> [UInt8]? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

private struct DominantColorBin {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var weight: CGFloat = 0

    mutating func add(red: CGFloat, green: CGFloat, blue: CGFloat, weight: CGFloat) {
        self.red += red * weight
        self.green += green * weight
        self.blue += blue * weight
        self.weight += weight
    }
}

private extension Array where Element == DominantColorBin {
    func significantHueGroupCount(relativeTo maxWeight: CGFloat) -> Int {
        guard maxWeight > 0 else { return 0 }
        let totalWeight = reduce(CGFloat(0)) { $0 + $1.weight }
        let active = map { bin in
            bin.weight >= maxWeight * 0.18 && bin.weight >= totalWeight * 0.045
        }
        guard active.contains(true) else { return 0 }

        var groups = 0
        for index in indices where active[index] {
            let previous = index == startIndex ? endIndex - 1 : index - 1
            if !active[previous] {
                groups += 1
            }
        }
        return groups
    }
}
