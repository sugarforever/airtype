import AppKit
import SwiftUI

/// Settings window now redirects to the main dashboard window.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var hotkeyManager: HotkeyManager?

    func show() {
        MainWindowController.shared.showSettings()
    }

    func close() {
        MainWindowController.shared.close()
    }
}
