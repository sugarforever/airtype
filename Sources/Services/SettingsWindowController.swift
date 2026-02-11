import AppKit
import SwiftUI

/// Settings window now redirects to the main dashboard window.
class SettingsWindowController {
    static let shared = SettingsWindowController()

    var hotkeyManager: HotkeyManager?

    func show() {
        MainWindowController.shared.show()
    }

    func close() {
        MainWindowController.shared.close()
    }
}
