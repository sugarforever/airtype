import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import DashboardCore
#endif

@MainActor
struct WindowActivationCoordinator {
    let makeRegular: () -> Void
    let orderWindowFront: () -> Void
    let activateApplication: () -> Void

    func present() {
        makeRegular()
        orderWindowFront()
        activateApplication()
    }

    static func present(_ window: NSWindow) {
        Self(
            makeRegular: { _ = NSApp.setActivationPolicy(.regular) },
            orderWindowFront: { window.makeKeyAndOrderFront(nil) },
            activateApplication: { NSApp.activate(ignoringOtherApps: true) }
        ).present()
    }
}

/// Manages the main dashboard window as a separate NSWindow
@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var windowDelegate: NSWindowDelegate?
    private let dashboardModel = DashboardModel()
    private lazy var historyModel = HistoryPageModel(copyText: Self.copyToPasteboard)
    var hotkeyManager: HotkeyManager?
    var vocabularyModel: VocabularyPageModel?

    func show(destination: DashboardDestination? = nil) {
        debugLog("MainWindowController.show() called")

        if let destination {
            dashboardModel.destination = destination
        }

        if let existingWindow = window {
            debugLog("Showing existing main window")
            WindowActivationCoordinator.present(existingWindow)
            return
        }

        debugLog("Creating new main window")

        guard let hotkeyManager = hotkeyManager else {
            debugLog("ERROR: hotkeyManager not set on MainWindowController")
            return
        }

        guard let vocabularyModel = vocabularyModel else {
            debugLog("ERROR: vocabularyModel not set on MainWindowController")
            return
        }

        let mainView = MainView(
            settings: Settings.shared,
            hotkeyManager: hotkeyManager,
            dashboardModel: dashboardModel,
            historyModel: historyModel,
            vocabularyModel: vocabularyModel
        )

        let hostingView = NSHostingView(rootView: mainView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 900, height: 680)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Airtype"
        newWindow.contentView = hostingView
        newWindow.setContentSize(NSSize(width: 900, height: 680))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .normal
        newWindow.contentMinSize = NSSize(width: 760, height: 560)

        let delegate = MainWindowDelegate { [weak self] in
            self?.window = nil
            self?.windowDelegate = nil
        }
        self.windowDelegate = delegate
        newWindow.delegate = delegate

        self.window = newWindow

        // Show in Dock while window is open so user can switch back to it
        WindowActivationCoordinator.present(newWindow)

        debugLog("Main window should now be visible")
    }

    func close() {
        window?.close()
        window = nil
    }

    func showSettings() {
        dashboardModel.showSettings()
        show()
    }

    private var wizardWindow: NSWindow?
    private var wizardWindowDelegate: NSWindowDelegate?

    func showWizard() {
        debugLog("MainWindowController.showWizard() called")

        if let existing = wizardWindow {
            WindowActivationCoordinator.present(existing)
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

        WindowActivationCoordinator.present(newWindow)
    }

    func closeWizard() {
        wizardWindow?.close()
        wizardWindow = nil
        wizardWindowDelegate = nil
    }

    private static func copyToPasteboard(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
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
