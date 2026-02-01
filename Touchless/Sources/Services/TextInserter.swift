import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Inserts text at the current cursor position using system paste
class TextInserter {

    /// Check if accessibility is enabled
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Insert text at current cursor position
    /// Uses clipboard + paste for reliable cross-app insertion
    func insert(text: String) async throws {
        debugLog("TextInserter.insert called with: \(text)")

        // Check accessibility permission
        if !hasAccessibilityPermission {
            debugLog("WARNING: Accessibility permission NOT granted!")
            debugLog("Requesting accessibility permission...")
            // This will prompt the user
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            debugLog("AXIsProcessTrustedWithOptions returned: \(trusted)")

            if !trusted {
                throw TextInsertionError.noAccessibilityPermission
            }
        } else {
            debugLog("Accessibility permission granted")
        }

        // Store current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        debugLog("Previous clipboard: \(previousContents ?? "nil")")

        // Set our text to clipboard
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        debugLog("Clipboard set success: \(success)")

        // Verify clipboard
        let verify = pasteboard.string(forType: .string)
        debugLog("Clipboard verify: \(verify ?? "nil")")

        // Small delay to ensure clipboard is ready
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Simulate Cmd+V paste
        debugLog("Simulating Cmd+V...")
        simulatePaste()

        // Wait for paste to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Restore previous clipboard content (optional - comment out to debug)
        // if let previous = previousContents {
        //     pasteboard.clearContents()
        //     pasteboard.setString(previous, forType: .string)
        // }

        debugLog("Text insertion complete")
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key down: Cmd+V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true) else {
            debugLog("Failed to create keyDown event")
            return
        }
        keyDown.flags = .maskCommand

        // Key up: Cmd+V
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            debugLog("Failed to create keyUp event")
            return
        }
        keyUp.flags = .maskCommand

        // Post events
        keyDown.post(tap: .cghidEventTap)
        debugLog("Posted keyDown event")

        // Small delay between key down and up
        usleep(50000) // 50ms

        keyUp.post(tap: .cghidEventTap)
        debugLog("Posted keyUp event")
    }
}

enum TextInsertionError: LocalizedError {
    case noAccessibilityPermission

    var errorDescription: String? {
        switch self {
        case .noAccessibilityPermission:
            return "Accessibility permission required. Please enable in System Settings → Privacy & Security → Accessibility"
        }
    }
}
