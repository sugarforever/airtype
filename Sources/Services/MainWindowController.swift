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

        // Show in Dock while window is open so user can switch back to it
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        debugLog("Main window should now be visible")
    }

    func close() {
        window?.close()
        window = nil
    }

    private var wizardWindow: NSWindow?
    private var wizardWindowDelegate: NSWindowDelegate?

    func showWizard() {
        debugLog("MainWindowController.showWizard() called")

        if let existing = wizardWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let wizardView = SetupWizardView {
            self.closeWizard()
            Settings.shared.hasCompletedSetup = true
            self.show()
        }

        let hostingView = NSHostingView(rootView: wizardView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 520)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Airtype Setup"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .normal

        let delegate = MainWindowDelegate { [weak self] in
            self?.wizardWindow = nil
            self?.wizardWindowDelegate = nil
        }
        self.wizardWindowDelegate = delegate
        newWindow.delegate = delegate

        self.wizardWindow = newWindow

        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWizard() {
        wizardWindow?.close()
        wizardWindow = nil
        wizardWindowDelegate = nil
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
