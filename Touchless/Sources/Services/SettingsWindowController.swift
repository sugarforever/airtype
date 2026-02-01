import AppKit
import SwiftUI

/// Manages the settings window as a separate NSWindow
class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var windowDelegate: NSWindowDelegate?

    func show() {
        print("[DEBUG] SettingsWindowController.show() called")

        if let existingWindow = window {
            print("[DEBUG] Showing existing window")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        print("[DEBUG] Creating new settings window")

        let settingsView = SettingsView(settings: Settings.shared, onClose: { [weak self] in
            self?.window?.close()
        })

        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 550)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 550),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Touchless Settings"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating  // Make sure it appears above other windows

        let delegate = WindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        self.windowDelegate = delegate
        newWindow.delegate = delegate

        self.window = newWindow

        // For menu bar apps, we need to activate the app first
        NSApp.setActivationPolicy(.accessory)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        print("[DEBUG] Settings window should now be visible")
    }

    func close() {
        window?.close()
        window = nil
    }
}

private class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
