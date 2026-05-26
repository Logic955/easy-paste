import AppKit

@MainActor
func runApplication() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

runApplication()
