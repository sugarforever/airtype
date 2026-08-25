import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Inserts text at the current cursor position through the system pasteboard.
@MainActor
final class TextInserter {
    typealias PasteHandler = @MainActor (String) async throws -> Void

    private let isAccessibilityTrusted: () -> Bool
    private let requestAccessibilityTrust: () -> Bool
    private let paste: PasteHandler

    init() {
        isAccessibilityTrusted = { AXIsProcessTrusted() }
        requestAccessibilityTrust = {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        paste = Self.insertByPaste
    }

    init(
        isAccessibilityTrusted: @escaping () -> Bool,
        requestAccessibilityTrust: @escaping () -> Bool,
        paste: @escaping PasteHandler
    ) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityTrust = requestAccessibilityTrust
        self.paste = paste
    }

    func insert(text: String) async throws {
        if !isAccessibilityTrusted() {
            guard requestAccessibilityTrust() else {
                throw TextInsertionError.noAccessibilityPermission
            }
        }
        try await paste(text)
    }

    private static func insertByPaste(text: String) async throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextInsertionError.pasteboardUnavailable
        }

        try await Task.sleep(for: .milliseconds(100))
        try simulatePaste()
        try await Task.sleep(for: .milliseconds(200))
    }

    private static func simulatePaste() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
            )
        else { throw TextInsertionError.eventCreationFailed }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        try? awaitKeyGap()
        keyUp.post(tap: .cghidEventTap)
    }

    private static func awaitKeyGap() throws {
        usleep(50_000)
    }
}

enum TextInsertionError: LocalizedError, Equatable {
    case noAccessibilityPermission
    case pasteboardUnavailable
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .noAccessibilityPermission:
            return "Accessibility permission required. Please enable in System Settings → Privacy & Security → Accessibility"
        case .pasteboardUnavailable:
            return "The system pasteboard is unavailable"
        case .eventCreationFailed:
            return "Unable to create a system paste event"
        }
    }
}
