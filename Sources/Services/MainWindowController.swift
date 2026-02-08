import AppKit
import SwiftUI

/// Manages the main dashboard window as a separate NSWindow
class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var windowDelegate: NSWindowDelegate?
    var hotkeyManager: HotkeyManager?

    func show() {
        debugLog("MainWindowController.show() called")

        if let existingWindow = window {
            debugLog("Showing existing main window")
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        debugLog("Creating new main window")

        guard let hotkeyManager = hotkeyManager else {
            debugLog("ERROR: hotkeyManager not set on MainWindowController")
            return
        }

        let mainView = MainView(settings: Settings.shared, hotkeyManager: hotkeyManager)

        let hostingView = NSHostingView(rootView: mainView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 700)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Airtype"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .normal

        let delegate = MainWindowDelegate { [weak self] in
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

        debugLog("Main window should now be visible")
    }

    func close() {
        window?.close()
        window = nil
    }
}

private class MainWindowDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
