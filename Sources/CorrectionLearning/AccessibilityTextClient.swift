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
    case failed
}

public enum AccessibilityTrackingEvent: Sendable {
    case valueChanged(editedText: String?)
    case focusLost
}

public enum AccessibilityTextError: Error, Equatable {
    case permissionDenied
    case insertionFailed
}

enum AccessibilitySetDisposition: Equatable {
    case inserted
    case unsupported
    case failed

    static func classify(_ result: AXError) -> Self {
        switch result {
        case .success:
            return .inserted
        case .attributeUnsupported, .notImplemented:
            return .unsupported
        default:
            return .failed
        }
    }
}

enum AccessibilityObservationRegistration {
    enum Notification: Equatable {
        case valueChanged
        case selectedTextChanged
        case focusChanged
    }

    static func isComplete(
        valueChanged: AXError,
        selectedTextChanged: AXError,
        focusChanged: AXError
    ) -> Bool {
        valueChanged == .success
            && selectedTextChanged == .success
            && focusChanged == .success
    }

    static func cleanUpIncompleteRegistration(
        valueChanged: AXError,
        selectedTextChanged: AXError,
        focusChanged: AXError,
        remove: (Notification) -> Void
    ) {
        guard !isComplete(
            valueChanged: valueChanged,
            selectedTextChanged: selectedTextChanged,
            focusChanged: focusChanged
        ) else { return }
        if valueChanged == .success { remove(.valueChanged) }
        if selectedTextChanged == .success { remove(.selectedTextChanged) }
        if focusChanged == .success { remove(.focusChanged) }
    }
}

struct AccessibilityInsertedRangeTracker {
    private(set) var insertedRange: CFRange
    private var documentLength: Int
    private let maximumSnapshotLength: Int
    private var selectionBeforeEdit: CFRange
    private var selectionDocumentLength: Int
    private var previousSelection: CFRange?
    private var previousSelectionDocumentLength: Int?
    private var canTrack = true

    init(
        insertedRange: CFRange,
        documentLength: Int,
        maximumSnapshotLength: Int
    ) {
        self.insertedRange = insertedRange
        self.documentLength = documentLength
        self.maximumSnapshotLength = maximumSnapshotLength
        self.selectionBeforeEdit = CFRange(
            location: Self.upperBound(of: insertedRange) ?? -1,
            length: 0
        )
        self.selectionDocumentLength = documentLength
        self.previousSelection = nil
        self.previousSelectionDocumentLength = nil
    }

    @discardableResult
    mutating func recordSelection(
        _ selection: CFRange,
        observedDocumentLength: Int? = nil
    ) -> Bool {
        guard canTrack else { return false }
        let observedDocumentLength = observedDocumentLength ?? documentLength
        guard Self.isValid(selection, inDocumentLength: observedDocumentLength) else {
            canTrack = false
            return false
        }
        previousSelection = selectionBeforeEdit
        previousSelectionDocumentLength = selectionDocumentLength
        selectionBeforeEdit = selection
        selectionDocumentLength = observedDocumentLength
        return true
    }

    mutating func rangeForSnapshot(
        postEditSelectedRange: CFRange,
        documentLength newDocumentLength: Int
    ) -> CFRange? {
        guard canTrack,
              Self.isValid(postEditSelectedRange, inDocumentLength: newDocumentLength),
              let oldUpperBound = Self.upperBound(of: insertedRange) else {
            return nil
        }

        let delta = newDocumentLength - documentLength
        let editSelection: CFRange
        if Self.isEqual(selectionBeforeEdit, postEditSelectedRange) {
            // A same-length value change cannot reveal whether this selection
            // is pre- or post-edit, so learning from it could cross a boundary.
            guard delta != 0 else { return nil }

            if selectionDocumentLength == documentLength {
                // The caret did not move (for example, forward delete). The
                // current selection is the edit origin; older caret moves are
                // unrelated history and must not influence the range.
                editSelection = selectionBeforeEdit
            } else {
                // Some apps publish the post-edit selection before the value
                // notification. Only use its predecessor when document-length
                // generations prove the two observations straddle this edit.
                guard selectionDocumentLength == newDocumentLength,
                      previousSelectionDocumentLength == documentLength,
                      let previousSelection,
                      Self.isPlausibleTransition(
                        from: previousSelection,
                        to: postEditSelectedRange,
                        documentDelta: delta
                      ) else { return nil }
                editSelection = previousSelection
            }
        } else {
            // If the latest selection belongs to another document-length
            // generation, notification coalescing made the edit ambiguous.
            guard selectionDocumentLength == documentLength else { return nil }
            editSelection = selectionBeforeEdit
        }
        guard Self.isValid(editSelection, inDocumentLength: documentLength),
              let selectionUpperBound = Self.upperBound(of: editSelection) else {
            return nil
        }

        var updatedRange = insertedRange

        if editSelection.length == 0,
           editSelection.location == insertedRange.location {
            if delta > 0 {
                guard let location = Self.adding(delta, to: updatedRange.location) else {
                    return nil
                }
                updatedRange.location = location
            } else if delta < 0 {
                if postEditSelectedRange.location < insertedRange.location {
                    guard let location = Self.adding(delta, to: updatedRange.location) else {
                        return nil
                    }
                    updatedRange.location = location
                } else if postEditSelectedRange.location == insertedRange.location {
                    guard let length = Self.adding(delta, to: updatedRange.length) else {
                        return nil
                    }
                    updatedRange.length = length
                } else {
                    return nil
                }
            }
        } else if editSelection.length == 0,
                  editSelection.location == oldUpperBound {
            if delta < 0,
               postEditSelectedRange.location < oldUpperBound {
                guard let length = Self.adding(delta, to: updatedRange.length) else {
                    return nil
                }
                updatedRange.length = length
            }
        } else if selectionUpperBound <= insertedRange.location {
            guard let location = Self.adding(delta, to: updatedRange.location) else {
                return nil
            }
            updatedRange.location = location
        } else if editSelection.location >= oldUpperBound {
            // Edits wholly after the insertion do not move or resize its range.
        } else if editSelection.location >= insertedRange.location,
                  selectionUpperBound <= oldUpperBound {
            guard let length = Self.adding(delta, to: updatedRange.length) else {
                return nil
            }
            updatedRange.length = length
        } else {
            // The edit selection crosses an insertion boundary, so the inserted
            // text can no longer be isolated without reading adjacent content.
            return nil
        }

        guard Self.isValid(updatedRange, inDocumentLength: newDocumentLength),
              updatedRange.length > 0,
              updatedRange.length <= maximumSnapshotLength else {
            return nil
        }

        insertedRange = updatedRange
        documentLength = newDocumentLength
        selectionBeforeEdit = postEditSelectedRange
        selectionDocumentLength = newDocumentLength
        previousSelection = nil
        previousSelectionDocumentLength = nil
        return updatedRange
    }

    private static func upperBound(of range: CFRange) -> Int? {
        adding(range.length, to: range.location)
    }

    private static func isEqual(_ lhs: CFRange, _ rhs: CFRange) -> Bool {
        lhs.location == rhs.location && lhs.length == rhs.length
    }

    private static func isPlausibleTransition(
        from selection: CFRange,
        to postEditSelection: CFRange,
        documentDelta: Int
    ) -> Bool {
        guard postEditSelection.length == 0 else { return false }
        if selection.length == 0 {
            if documentDelta > 0 {
                return adding(documentDelta, to: selection.location)
                    == postEditSelection.location
            }
            if documentDelta < 0 {
                return postEditSelection.location == selection.location
                    || adding(documentDelta, to: selection.location)
                        == postEditSelection.location
            }
            return false
        }

        guard let replacementLength = adding(documentDelta, to: selection.length),
              replacementLength >= 0,
              let expectedCaret = adding(replacementLength, to: selection.location) else {
            return false
        }
        return postEditSelection.location == expectedCaret
    }

    private static func adding(_ offset: Int, to value: Int) -> Int? {
        let (result, overflow) = value.addingReportingOverflow(offset)
        return overflow ? nil : result
    }

    private static func isValid(_ range: CFRange, inDocumentLength length: Int) -> Bool {
        guard length >= 0,
              range.location >= 0,
              range.length >= 0,
              let upperBound = upperBound(of: range) else {
            return false
        }
        return upperBound <= length
    }
}

@MainActor
public protocol AccessibilityTextClientProtocol: AnyObject {
    func insert(text: String, observationEnabled: Bool) -> AccessibilityInsertionAttempt
    func observe(
        sessionID: UUID,
        handler: @escaping (AccessibilityTrackingEvent) -> Void
    ) -> Bool
    func stopObserving(sessionID: UUID)
}

@MainActor
public final class AccessibilityTextClient: AccessibilityTextClientProtocol {
    private struct Session {
        let element: AccessibilityElementReference
        let application: AXUIElement
        let processID: pid_t
        let snapshotState: AccessibilitySnapshotState
        var observer: AXObserver?
        var observationBox: AccessibilityObservationBox?
    }

    private var sessions: [UUID: Session] = [:]
    private let snapshotQueue = DispatchQueue(
        label: "com.airtype.accessibility-snapshot",
        qos: .utility
    )

    public init() {}

    public func insert(
        text: String,
        observationEnabled: Bool
    ) -> AccessibilityInsertionAttempt {
        guard AXIsProcessTrusted() else { return .permissionDenied }
        let systemWide = AXUIElementCreateSystemWide()
        guard
            let application = elementAttribute(systemWide, kAXFocusedApplicationAttribute),
            let element = elementAttribute(application, kAXFocusedUIElementAttribute)
        else { return .unsupported }

        var processID: pid_t = 0
        AXUIElementGetPid(element, &processID)
        let bundleID = NSRunningApplication(processIdentifier: processID)?.bundleIdentifier ?? "unknown"

        if observationEnabled {
            // Bound every optional learning read, including the pre-insertion
            // selection lookup. Ambiguous write timeouts never trigger paste.
            _ = AXUIElementSetMessagingTimeout(element, 0.1)
        }
        let selectedRange = observationEnabled
            ? rangeAttribute(element, kAXSelectedTextRangeAttribute)
            : nil
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        switch AccessibilitySetDisposition.classify(setResult) {
        case .unsupported:
            return .unsupported
        case .failed:
            return .failed
        case .inserted:
            break
        }

        guard observationEnabled,
              let selectedRange,
              selectedRange.location >= 0,
              selectedRange.length >= 0 else {
            return .insertedWithoutObservation
        }

        guard let documentLength = integerAttribute(element, kAXNumberOfCharactersAttribute),
              documentLength >= 0 else {
            return .insertedWithoutObservation
        }

        let insertedLength = (text as NSString).length
        let (insertedUpperBound, rangeOverflow) = selectedRange.location
            .addingReportingOverflow(insertedLength)
        let insertedRange = CFRange(location: selectedRange.location, length: insertedLength)
        guard insertedLength > 0,
              insertedLength <= 4_096,
              !rangeOverflow,
              insertedUpperBound <= documentLength,
              stringForRange(element, range: insertedRange) == text else {
            return .insertedWithoutObservation
        }

        let maximumSnapshotLength = min(
            4_096,
            insertedLength + max(insertedLength, 64)
        )
        let sessionID = UUID()
        sessions[sessionID] = Session(
            element: AccessibilityElementReference(element),
            application: application,
            processID: processID,
            snapshotState: AccessibilitySnapshotState(tracker: AccessibilityInsertedRangeTracker(
                insertedRange: insertedRange,
                documentLength: documentLength,
                maximumSnapshotLength: maximumSnapshotLength
            )),
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
        guard var session = sessions[sessionID],
              session.observer == nil,
              session.observationBox == nil else { return false }
        let box = AccessibilityObservationBox(sessionID: sessionID, handler: handler)
        var observer: AXObserver?
        guard AXObserverCreate(session.processID, accessibilityObserverCallback, &observer) == .success,
              let observer else { return false }

        let context = Unmanaged.passUnretained(box).toOpaque()
        let valueResult = AXObserverAddNotification(
            observer,
            session.element.element,
            kAXValueChangedNotification as CFString,
            context
        )
        let selectionResult = AXObserverAddNotification(
            observer,
            session.element.element,
            kAXSelectedTextChangedNotification as CFString,
            context
        )
        let focusResult = AXObserverAddNotification(
            observer,
            session.application,
            kAXFocusedUIElementChangedNotification as CFString,
            context
        )
        guard AccessibilityObservationRegistration.isComplete(
            valueChanged: valueResult,
            selectedTextChanged: selectionResult,
            focusChanged: focusResult
        ) else {
            AccessibilityObservationRegistration.cleanUpIncompleteRegistration(
                valueChanged: valueResult,
                selectedTextChanged: selectionResult,
                focusChanged: focusResult
            ) { notification in
                switch notification {
                case .valueChanged:
                    AXObserverRemoveNotification(
                        observer,
                        session.element.element,
                        kAXValueChangedNotification as CFString
                    )
                case .selectedTextChanged:
                    AXObserverRemoveNotification(
                        observer,
                        session.element.element,
                        kAXSelectedTextChangedNotification as CFString
                    )
                case .focusChanged:
                    AXObserverRemoveNotification(
                        observer,
                        session.application,
                        kAXFocusedUIElementChangedNotification as CFString
                    )
                }
            }
            return false
        }

        box.notificationHandler = { [weak self, weak box] notification in
            guard let self, let box else { return }
            self.handle(notification: notification, box: box)
        }
        session.observer = observer
        session.observationBox = box
        sessions[sessionID] = session
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        return true
    }

    public func stopObserving(sessionID: UUID) {
        guard let session = sessions.removeValue(forKey: sessionID) else { return }
        session.snapshotState.invalidate()
        session.observationBox?.invalidate()
        guard let observer = session.observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    private func handle(notification: String, box: AccessibilityObservationBox) {
        guard box.isActive,
              let session = sessions[box.sessionID] else { return }
        switch notification {
        case kAXSelectedTextChangedNotification:
            enqueueSelectionSnapshot(for: session, box: box)
        case kAXValueChangedNotification:
            enqueueValueSnapshot(for: session, box: box)
        case kAXFocusedUIElementChangedNotification:
            enqueueFocusLoss(for: session, box: box)
        default:
            return
        }
    }

    private func enqueueSelectionSnapshot(
        for session: Session,
        box: AccessibilityObservationBox
    ) {
        let element = session.element
        let snapshotState = session.snapshotState
        snapshotQueue.async { [weak self, weak box] in
            guard snapshotState.isActive else { return }
            guard let selection = Self.rangeAttribute(
                    element.element,
                    kAXSelectedTextRangeAttribute
                  ),
                  let documentLength = Self.integerAttribute(
                    element.element,
                    kAXNumberOfCharactersAttribute
                  ),
                  snapshotState.recordSelection(
                    selection,
                    observedDocumentLength: documentLength
                  ) else {
                DispatchQueue.main.async {
                    guard let self, let box, box.isActive else { return }
                    box.handler(.valueChanged(editedText: nil))
                    self.stopObserving(sessionID: box.sessionID)
                }
                return
            }
        }
    }

    private func enqueueValueSnapshot(
        for session: Session,
        box: AccessibilityObservationBox
    ) {
        let element = session.element
        let snapshotState = session.snapshotState
        snapshotQueue.async { [weak self, weak box] in
            guard snapshotState.isActive,
                  let selectedRange = Self.rangeAttribute(
                    element.element,
                    kAXSelectedTextRangeAttribute
                  ),
                  let documentLength = Self.integerAttribute(
                    element.element,
                    kAXNumberOfCharactersAttribute
                  ),
                  let range = snapshotState.rangeForSnapshot(
                    postEditSelectedRange: selectedRange,
                    documentLength: documentLength
                  ),
                  let editedText = Self.stringForRange(element.element, range: range) else {
                DispatchQueue.main.async {
                    guard let self, let box, box.isActive else { return }
                    box.handler(.valueChanged(editedText: nil))
                    self.stopObserving(sessionID: box.sessionID)
                }
                return
            }
            DispatchQueue.main.async {
                guard let box, box.isActive else { return }
                box.handler(.valueChanged(editedText: editedText))
            }
        }
    }

    private func enqueueFocusLoss(
        for session: Session,
        box: AccessibilityObservationBox
    ) {
        let snapshotState = session.snapshotState
        snapshotQueue.async {
            guard snapshotState.isActive else { return }
            DispatchQueue.main.async { [weak box] in
                guard let box, box.isActive else { return }
                box.handler(.focusLost)
            }
        }
    }

    private func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    nonisolated private static func integerAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private func integerAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        Self.integerAttribute(element, attribute)
    }

    nonisolated private static func rangeAttribute(
        _ element: AXUIElement,
        _ attribute: String
    ) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func rangeAttribute(_ element: AXUIElement, _ attribute: String) -> CFRange? {
        Self.rangeAttribute(element, attribute)
    }

    nonisolated private static func stringForRange(
        _ element: AXUIElement,
        range: CFRange
    ) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    private func stringForRange(_ element: AXUIElement, range: CFRange) -> String? {
        Self.stringForRange(element, range: range)
    }
}

private final class AccessibilityElementReference: @unchecked Sendable {
    let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }
}

private final class AccessibilitySnapshotState: @unchecked Sendable {
    private let lock = NSLock()
    private var tracker: AccessibilityInsertedRangeTracker
    private var active = true

    init(tracker: AccessibilityInsertedRangeTracker) {
        self.tracker = tracker
    }

    var isActive: Bool {
        lock.withLock { active }
    }

    func recordSelection(
        _ selection: CFRange,
        observedDocumentLength: Int? = nil
    ) -> Bool {
        lock.withLock {
            guard active else { return false }
            guard tracker.recordSelection(
                selection,
                observedDocumentLength: observedDocumentLength
            ) else {
                active = false
                return false
            }
            return true
        }
    }

    func rangeForSnapshot(
        postEditSelectedRange: CFRange,
        documentLength: Int
    ) -> CFRange? {
        lock.withLock {
            guard active else { return nil }
            guard let range = tracker.rangeForSnapshot(
                postEditSelectedRange: postEditSelectedRange,
                documentLength: documentLength
            ) else {
                active = false
                return nil
            }
            return range
        }
    }

    func invalidate() {
        lock.withLock { active = false }
    }
}

@MainActor
private final class AccessibilityObservationBox {
    let sessionID: UUID
    let handler: (AccessibilityTrackingEvent) -> Void
    var notificationHandler: ((String) -> Void)?
    private(set) var isActive = true

    init(sessionID: UUID, handler: @escaping (AccessibilityTrackingEvent) -> Void) {
        self.sessionID = sessionID
        self.handler = handler
    }

    func invalidate() {
        isActive = false
        notificationHandler = nil
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
    let notificationName = notification as String
    DispatchQueue.main.async { [weak box] in
        guard let box, box.isActive else { return }
        box.notificationHandler?(notificationName)
    }
}
