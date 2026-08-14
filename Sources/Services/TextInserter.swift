import AppKit
import Carbon.HIToolbox
import ApplicationServices
#if SWIFT_PACKAGE
import CorrectionLearningCore
#endif

/// Inserts text at the current cursor position, preferring direct Accessibility insertion.
@MainActor
final class TextInserter {
    private let coordinator: TextInsertionCoordinator

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    init(accessibilityClient: (any AccessibilityTextClientProtocol)? = nil) {
        let client = accessibilityClient ?? AccessibilityTextClient()
        coordinator = TextInsertionCoordinator(client: client) { text in
            try await Self.insertByPaste(text: text)
        }
    }

    @discardableResult
    func insert(text: String) async throws -> TextInsertionOutcome {
        do {
            return try await coordinator.insert(text: text)
        } catch AccessibilityTextError.permissionDenied {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            guard AXIsProcessTrustedWithOptions(options) else {
                throw TextInsertionError.noAccessibilityPermission
            }
            return try await coordinator.insert(text: text)
        }
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

enum TextInsertionError: LocalizedError {
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
