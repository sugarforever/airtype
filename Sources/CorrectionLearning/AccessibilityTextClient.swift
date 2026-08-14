import AppKit
import ApplicationServices
import Foundation

public struct AccessibilityInsertion: Equatable, Sendable {
    public let sessionID: UUID
    public let originalText: String
    public let applicationBundleID: String

    public init(sessionID: UUID, originalText: String, applicationBundleID: String) {
        self.sessionID = sessionID
        self.originalText = originalText
        self.applicationBundleID = applicationBundleID
    }
}

public enum AccessibilityInsertionAttempt: Equatable, Sendable {
    case observable(AccessibilityInsertion)
    case insertedWithoutObservation
    case unsupported
    case permissionDenied
}

public enum AccessibilityTrackingEvent: Sendable {
    case valueChanged
    case focusLost
}

public enum AccessibilityTextError: Error, Equatable {
    case permissionDenied
}

@MainActor
public protocol AccessibilityTextClientProtocol: AnyObject {
    func insert(text: String) -> AccessibilityInsertionAttempt
    func observe(
        sessionID: UUID,
        handler: @escaping (AccessibilityTrackingEvent) -> Void
    ) -> Bool
    func stopObserving(sessionID: UUID)
    func editedText(sessionID: UUID) -> String?
}

@MainActor
public final class AccessibilityTextClient: AccessibilityTextClientProtocol {
    private struct Session {
        let element: AXUIElement
        let application: AXUIElement
        let processID: pid_t
        let prefix: String
        let suffix: String
        var observer: AXObserver?
        var observationBox: AccessibilityObservationBox?
    }

    private var sessions: [UUID: Session] = [:]

    public init() {}

    public func insert(text: String) -> AccessibilityInsertionAttempt {
        guard AXIsProcessTrusted() else { return .permissionDenied }
        let systemWide = AXUIElementCreateSystemWide()
        guard
            let application = elementAttribute(systemWide, kAXFocusedApplicationAttribute),
            let element = elementAttribute(application, kAXFocusedUIElementAttribute)
        else { return .unsupported }

        var processID: pid_t = 0
        AXUIElementGetPid(element, &processID)
        let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier ?? "unknown"

        let fullValue = stringAttribute(element, kAXValueAttribute)
        let selectedRange = rangeAttribute(element, kAXSelectedTextRangeAttribute)
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setResult == .success else { return .unsupported }
        guard let fullValue, let selectedRange else { return .insertedWithoutObservation }

        let value = fullValue as NSString
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= value.length else {
            return .insertedWithoutObservation
        }

        let sessionID = UUID()
        sessions[sessionID] = Session(
            element: element,
            application: application,
            processID: processID,
            prefix: value.substring(to: selectedRange.location),
            suffix: value.substring(from: selectedRange.location + selectedRange.length),
            observer: nil,
            observationBox: nil
        )
        return .observable(AccessibilityInsertion(
            sessionID: sessionID,
            originalText: text,
            applicationBundleID: bundleID
        ))
    }

    public func observe(
        sessionID: UUID,
        handler: @escaping (AccessibilityTrackingEvent) -> Void
    ) -> Bool {
        guard var session = sessions[sessionID] else { return false }
        let box = AccessibilityObservationBox(handler: handler)
        var observer: AXObserver?
        guard AXObserverCreate(session.processID, accessibilityObserverCallback, &observer) == .success,
              let observer else { return false }

        let context = Unmanaged.passUnretained(box).toOpaque()
        let valueResult = AXObserverAddNotification(
            observer,
            session.element,
            kAXValueChangedNotification as CFString,
            context
        )
        let focusResult = AXObserverAddNotification(
            observer,
            session.application,
            kAXFocusedUIElementChangedNotification as CFString,
            context
        )
        guard valueResult == .success || focusResult == .success else { return false }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        session.observer = observer
        session.observationBox = box
        sessions[sessionID] = session
        return true
    }

    public func stopObserving(sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID),
              let observer = session.observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    public func editedText(sessionID: UUID) -> String? {
        guard let session = sessions[sessionID],
              let currentValue = stringAttribute(session.element, kAXValueAttribute) else {
            return nil
        }
        let current = currentValue as NSString
        let prefixLength = (session.prefix as NSString).length
        let suffixLength = (session.suffix as NSString).length
        guard current.hasPrefix(session.prefix),
              current.hasSuffix(session.suffix),
              prefixLength + suffixLength <= current.length else { return nil }
        return current.substring(with: NSRange(
            location: prefixLength,
            length: current.length - prefixLength - suffixLength
        ))
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }
}

private final class AccessibilityObservationBox {
    let handler: (AccessibilityTrackingEvent) -> Void

    init(handler: @escaping (AccessibilityTrackingEvent) -> Void) {
        self.handler = handler
    }
}

private func accessibilityObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let box = Unmanaged<AccessibilityObservationBox>.fromOpaque(context).takeUnretainedValue()
    let event: AccessibilityTrackingEvent = notification as String == kAXValueChangedNotification
        ? .valueChanged
        : .focusLost
    DispatchQueue.main.async { box.handler(event) }
}
