import AppKit

@MainActor
enum PanelGlassCapability {
    static var isAvailable: Bool {
        unavailableReason == nil
    }

    static var unavailableReason: String? {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            return L10n.t("settings.panelGlassUnavailableReduceTransparency")
        }
        return nil
    }
}
