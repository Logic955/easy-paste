import Carbon
import ApplicationServices
import AppKit
import EasyPasteCore
import Foundation

@MainActor
final class HotKeyController {
    struct RegistrationReport: Equatable {
        var shortcut: KeyboardShortcut
        var carbonStatus: OSStatus
        var accessibilityTrusted: Bool
        var eventTapEnabled: Bool
        var pasteHelperRunning: Bool

        var hasCarbonFailure: Bool { carbonStatus != noErr }
        var hasEventTapFailure: Bool { accessibilityTrusted && !eventTapEnabled }
        var hasPasteConflict: Bool {
            pasteHelperRunning && shortcut == .defaultActivation
        }

        static let initial = RegistrationReport(
            shortcut: .defaultActivation,
            carbonStatus: OSStatus(eventNotHandledErr),
            accessibilityTrusted: false,
            eventTapEnabled: false,
            pasteHelperRunning: false
        )
    }

    static let diagnosticsChangedNotification = Notification.Name("EasyPasteHotKeyDiagnosticsChanged")
    nonisolated(unsafe) private(set) static var latestReport = RegistrationReport.initial

    private let action: () -> Void
    nonisolated(unsafe) private var shortcut: KeyboardShortcut = .defaultActivation
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastFireAt = Date.distantPast

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register(shortcut: KeyboardShortcut) {
        unregister()
        self.shortcut = shortcut

        let hotKeyID = EventHotKeyID(signature: fourCharCode("EPST"), id: 1)

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }

                let pointer = UInt(bitPattern: userData)

                Task { @MainActor in
                    guard let rawPointer = UnsafeRawPointer(bitPattern: pointer) else {
                        return
                    }

                    let controller = Unmanaged<HotKeyController>.fromOpaque(rawPointer).takeUnretainedValue()
                    controller.fire()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        if status != noErr {
            NSLog("EasyPaste failed to register activation shortcut \(ShortcutFormatter.displayString(for: shortcut)) status=\(status); accessibility event tap fallback will still try to handle it")
        }
        let eventTapEnabled = startEventTapFallback()
        publishReport(carbonStatus: status, eventTapEnabled: eventTapEnabled)
        if Self.isPasteHelperRunning(), shortcut == .defaultActivation {
            NSLog("EasyPaste detected Paste helper running with the same default shortcut \(ShortcutFormatter.displayString(for: shortcut))")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { result, byte in
            (result << 8) + OSType(byte)
        }
    }

    private func fire() {
        let now = Date()
        guard now.timeIntervalSince(lastFireAt) > 0.18 else { return }
        lastFireAt = now
        action()
    }

    private func startEventTapFallback() -> Bool {
        guard eventTap == nil, AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userData in
                guard type == .keyDown, let userData else {
                    return Unmanaged.passUnretained(event)
                }

                guard let controller = HotKeyController.controller(from: userData),
                      controller.matches(event) else {
                    return Unmanaged.passUnretained(event)
                }

                let pointer = UInt(bitPattern: userData)
                Task { @MainActor in
                    guard let rawPointer = UnsafeRawPointer(bitPattern: pointer) else { return }
                    let controller = Unmanaged<HotKeyController>.fromOpaque(rawPointer).takeUnretainedValue()
                    controller.fire()
                }
                return nil
            },
            userInfo: userData
        ) else {
            NSLog("EasyPaste failed to create accessibility event tap fallback")
            return false
        }

        eventTap = tap
        eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    nonisolated private static func controller(from userData: UnsafeMutableRawPointer) -> HotKeyController? {
        let rawPointer = UnsafeRawPointer(userData)
        return Unmanaged<HotKeyController>.fromOpaque(rawPointer).takeUnretainedValue()
    }

    nonisolated private func matches(_ event: CGEvent) -> Bool {
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.keyCode else { return false }
        let flags = event.flags
        let required = shortcut.cgEventFlags
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        return flags.intersection(relevant) == required
    }

    private func publishReport(carbonStatus: OSStatus, eventTapEnabled: Bool) {
        Self.latestReport = RegistrationReport(
            shortcut: shortcut,
            carbonStatus: carbonStatus,
            accessibilityTrusted: AXIsProcessTrusted(),
            eventTapEnabled: eventTapEnabled,
            pasteHelperRunning: Self.isPasteHelperRunning()
        )
        NotificationCenter.default.post(name: Self.diagnosticsChangedNotification, object: nil)
    }

    static func isPasteHelperRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.wiheads.paste.mac-helper" || app.bundleIdentifier == "com.wiheads.paste"
        }
    }
}

private extension KeyboardShortcut {
    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        return flags
    }
}
