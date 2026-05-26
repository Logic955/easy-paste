import AppKit

@MainActor
enum EasyPasteThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "自动跟随系统"
        case .light: return "亮色"
        case .dark: return "暗色"
        }
    }
}

@MainActor
enum EasyPasteThemeStore {
    static let changedNotification = Notification.Name("EasyPasteThemeChanged")

    private static let defaultsKey = "themeMode"

    static var mode: EasyPasteThemeMode {
        get {
            let raw = UserDefaults.standard.string(forKey: defaultsKey)
            return raw.flatMap(EasyPasteThemeMode.init(rawValue:)) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }

    static var effectiveTheme: EasyPasteTheme {
        let isDark: Bool
        switch mode {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            isDark = match == .darkAqua
        }
        return EasyPasteTheme(isDark: isDark)
    }

    static var appearance: NSAppearance? {
        switch mode {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
struct EasyPasteTheme {
    let isDark: Bool

    var panelMaterial: NSVisualEffectView.Material { isDark ? .hudWindow : .popover }
    var panelBackground: NSColor {
        panelBackground(opacity: 1.0)
    }

    func panelBackground(opacity: Double) -> NSColor {
        let clamped = min(1.0, max(0.0, opacity))
        let darkAlpha = 0.04 + 0.52 * clamped
        let lightAlpha = 0.06 + 0.70 * clamped
        return isDark
            ? NSColor.black.withAlphaComponent(darkAlpha)
            : NSColor.white.withAlphaComponent(lightAlpha)
    }
    var panelSolidBackground: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.070, green: 0.078, blue: 0.090, alpha: 0.98)
            : NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.980, alpha: 0.98)
    }
    var panelBorder: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.10)
    }

    var cardBackground: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.070, green: 0.078, blue: 0.090, alpha: 0.78)
            : NSColor(calibratedWhite: 0.96, alpha: 0.82)
    }
    var cardBodyBackground: NSColor {
        isDark
            ? NSColor(calibratedRed: 0.074, green: 0.083, blue: 0.096, alpha: 0.98)
            : NSColor(calibratedWhite: 0.985, alpha: 0.96)
    }
    var primaryText: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.78)
    }
    var secondaryText: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.84)
            : NSColor.black.withAlphaComponent(0.56)
    }
    var footerText: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.58)
            : NSColor.black.withAlphaComponent(0.44)
    }
    var imageInfoText: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.78)
            : NSColor.black.withAlphaComponent(0.58)
    }
    var imageInfoChipBackground: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.085)
            : NSColor.black.withAlphaComponent(0.055)
    }

    var toolbarIcon: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.92)
            : NSColor.black.withAlphaComponent(0.62)
    }
    var pillBackground: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.white.withAlphaComponent(0.64)
    }
    var pillBorder: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.18)
            : NSColor.black.withAlphaComponent(0.08)
    }
    var pillText: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.96)
            : NSColor.black.withAlphaComponent(0.72)
    }
    var toolbarButtonBackgroundBase: NSColor { isDark ? .white : .black }

    var searchBackground: NSColor {
        isDark
            ? NSColor.black.withAlphaComponent(0.28)
            : NSColor.white.withAlphaComponent(0.74)
    }
    var searchBorder: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.20)
            : NSColor.black.withAlphaComponent(0.10)
    }
    var searchText: NSColor {
        isDark
            ? .white
            : NSColor.black.withAlphaComponent(0.78)
    }
    var searchPlaceholder: NSColor {
        isDark
            ? NSColor.white.withAlphaComponent(0.45)
            : NSColor.black.withAlphaComponent(0.36)
    }
}
