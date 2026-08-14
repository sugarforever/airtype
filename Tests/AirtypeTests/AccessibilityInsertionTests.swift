import XCTest
import ApplicationServices
@testable import CorrectionLearningCore

@MainActor
final class AccessibilityInsertionTests: XCTestCase {
    func testObservableAXInsertionReturnsTrackingSession() async throws {
        let client = FakeAccessibilityTextClient(
            insertionResult: .observable(AccessibilityInsertion(
                sessionID: UUID(),
                originalText: "hello",
                applicationBundleID: "com.example.editor"
            ))
        )
        var pasted = false
        let coordinator = TextInsertionCoordinator(client: client) { _ in pasted = true }

        let result = try await coordinator.insert(text: "hello", learningEnabled: true)

        guard case .accessibility(let insertion) = result else {
            return XCTFail("Expected observable Accessibility insertion")
        }
        XCTAssertEqual(insertion.originalText, "hello")
        XCTAssertFalse(pasted)
    }

    func testUnobservableAXInsertionDoesNotCreateTrackingSession() async throws {
        let client = FakeAccessibilityTextClient(insertionResult: .insertedWithoutObservation)
        let coordinator = TextInsertionCoordinator(client: client) { _ in }

        let result = try await coordinator.insert(text: "hello", learningEnabled: true)

        XCTAssertEqual(result, .accessibilityWithoutObservation)
    }

    func testUnsupportedAXInsertionFallsBackToPaste() async throws {
        let client = FakeAccessibilityTextClient(insertionResult: .unsupported)
        var pastedText: String?
        let coordinator = TextInsertionCoordinator(client: client) { pastedText = $0 }

        let result = try await coordinator.insert(text: "hello", learningEnabled: true)

        XCTAssertEqual(result, .paste)
        XCTAssertEqual(pastedText, "hello")
    }

    func testPermissionFailureDoesNotPaste() async {
        let client = FakeAccessibilityTextClient(insertionResult: .permissionDenied)
        var pasted = false
        let coordinator = TextInsertionCoordinator(client: client) { _ in pasted = true }

        do {
            _ = try await coordinator.insert(text: "hello", learningEnabled: true)
            XCTFail("Expected permission error")
        } catch {
            XCTAssertEqual(error as? AccessibilityTextError, .permissionDenied)
            XCTAssertFalse(pasted)
        }
    }

    func testLearningDisabledUsesInsertionWithoutCreatingAnObservableSession() async throws {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "hello",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(
            insertionResult: .observable(insertion),
            unobservedInsertionResult: .insertedWithoutObservation
        )
        let coordinator = TextInsertionCoordinator(client: client) { _ in }

        let result = try await coordinator.insert(text: "hello", learningEnabled: false)

        XCTAssertEqual(result, .accessibilityWithoutObservation)
        XCTAssertEqual(client.insertionObservationRequests, [false])
    }

    func testAmbiguousAXInsertionFailureNeverFallsBackToPaste() async {
        let client = FakeAccessibilityTextClient(insertionResult: .failed)
        var pasted = false
        let coordinator = TextInsertionCoordinator(client: client) { _ in pasted = true }

        do {
            _ = try await coordinator.insert(text: "hello", learningEnabled: true)
            XCTFail("Expected an indeterminate Accessibility insertion error")
        } catch {
            XCTAssertEqual(error as? AccessibilityTextError, .insertionFailed)
            XCTAssertFalse(pasted)
        }
    }

    func testCannotCompleteIsAnAmbiguousSetFailure() {
        XCTAssertEqual(AccessibilitySetDisposition.classify(.cannotComplete), .failed)
        XCTAssertEqual(AccessibilitySetDisposition.classify(.attributeUnsupported), .unsupported)
    }

    func testObservationRequiresValueSelectionAndFocusNotifications() {
        XCTAssertTrue(AccessibilityObservationRegistration.isComplete(
            valueChanged: .success,
            selectedTextChanged: .success,
            focusChanged: .success
        ))
        XCTAssertFalse(AccessibilityObservationRegistration.isComplete(
            valueChanged: .notificationUnsupported,
            selectedTextChanged: .success,
            focusChanged: .success
        ))
        XCTAssertFalse(AccessibilityObservationRegistration.isComplete(
            valueChanged: .success,
            selectedTextChanged: .notificationUnsupported,
            focusChanged: .success
        ))
        XCTAssertFalse(AccessibilityObservationRegistration.isComplete(
            valueChanged: .success,
            selectedTextChanged: .success,
            focusChanged: .notificationUnsupported
        ))
    }

    func testPartialObservationRegistrationCleansUpEverySuccessfulNotification() {
        var removed: [AccessibilityObservationRegistration.Notification] = []

        AccessibilityObservationRegistration.cleanUpIncompleteRegistration(
            valueChanged: .success,
            selectedTextChanged: .notificationUnsupported,
            focusChanged: .success
        ) { removed.append($0) }

        XCTAssertEqual(removed, [.valueChanged, .focusChanged])
    }

    func testAdjacentTypingDoesNotExpandTheInsertedRange() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 13,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(CFRange(location: 13, length: 0))

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 14, length: 0),
            documentLength: 14
        )

        XCTAssertEqual(snapshotRange?.location, 8)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testPostEditSelectionNotificationBeforeValueStillIsolatesAdjacentTyping() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 13,
            maximumSnapshotLength: 64
        )

        tracker.recordSelection(
            CFRange(location: 14, length: 0),
            observedDocumentLength: 14
        )
        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 14, length: 0),
            documentLength: 14
        )

        XCTAssertEqual(snapshotRange?.location, 8)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testCoalescedPostEditSelectionWithStaleHistoryIsDiscarded() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )

        // The user moved before the insertion and typed, but the asynchronous
        // selection read observed only the post-edit caret/document generation.
        tracker.recordSelection(
            CFRange(location: 3, length: 0),
            observedDocumentLength: 21
        )
        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 3, length: 0),
            documentLength: 21
        )

        XCTAssertNil(snapshotRange)
    }

    func testPostEditSelectionNotificationCannotHideCrossBoundaryEdit() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )

        tracker.recordSelection(CFRange(location: 7, length: 2))
        tracker.recordSelection(
            CFRange(location: 9, length: 0),
            observedDocumentLength: 20
        )
        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 9, length: 0),
            documentLength: 20
        )

        XCTAssertNil(snapshotRange)
    }

    func testShorterReplacementShrinksTheInsertedRange() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 12),
            documentLength: 30,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(CFRange(location: 8, length: 12))

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 18, length: 0),
            documentLength: 28
        )

        XCTAssertEqual(snapshotRange?.location, 8)
        XCTAssertEqual(snapshotRange?.length, 10)
    }

    func testEditBeforeInsertionShiftsRangeWithoutReadingThePrefix() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(CFRange(location: 2, length: 0))

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 3, length: 0),
            documentLength: 21
        )

        XCTAssertEqual(snapshotRange?.location, 9)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testForwardDeleteAfterInsertionDoesNotShrinkInsertedRange() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(CFRange(location: 13, length: 0))

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 13, length: 0),
            documentLength: 19
        )

        XCTAssertEqual(snapshotRange?.location, 8)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testForwardDeleteBeforeInsertionIgnoresStaleCaretHistory() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(
            CFRange(location: 15, length: 0),
            observedDocumentLength: 20
        )
        tracker.recordSelection(
            CFRange(location: 2, length: 0),
            observedDocumentLength: 20
        )

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 2, length: 0),
            documentLength: 19
        )

        XCTAssertEqual(snapshotRange?.location, 7)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testForwardDeleteAfterInsertionIgnoresStaleCaretHistory() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(
            CFRange(location: 2, length: 0),
            observedDocumentLength: 20
        )
        tracker.recordSelection(
            CFRange(location: 15, length: 0),
            observedDocumentLength: 20
        )

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 15, length: 0),
            documentLength: 19
        )

        XCTAssertEqual(snapshotRange?.location, 8)
        XCTAssertEqual(snapshotRange?.length, 5)
    }

    func testUnchangedCaretSameLengthEditWithSelectionHistoryIsDiscarded() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(
            CFRange(location: 15, length: 0),
            observedDocumentLength: 20
        )
        tracker.recordSelection(
            CFRange(location: 10, length: 0),
            observedDocumentLength: 20
        )

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 10, length: 0),
            documentLength: 20
        )

        XCTAssertNil(snapshotRange)
    }

    func testSameLengthEditCrossingInsertionBoundaryIsRejected() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )
        tracker.recordSelection(CFRange(location: 7, length: 2))

        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 9, length: 0),
            documentLength: 20
        )

        XCTAssertNil(snapshotRange)
    }

    func testInvalidSelectionAbandonsRangeTracking() {
        var tracker = AccessibilityInsertedRangeTracker(
            insertedRange: CFRange(location: 8, length: 5),
            documentLength: 20,
            maximumSnapshotLength: 64
        )

        tracker.recordSelection(CFRange(location: 21, length: 0))
        let snapshotRange = tracker.rangeForSnapshot(
            postEditSelectedRange: CFRange(location: 13, length: 0),
            documentLength: 20
        )

        XCTAssertNil(snapshotRange)
    }
}

@MainActor
final class TextEditTrackerTests: XCTestCase {
    func testFocusDepartureLearnsFinalTextOnce() async {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "Cloud Flower",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(
            insertionResult: .observable(insertion)
        )
        let learned = expectation(description: "learned")
        let recorder = LearnedTextRecorder(expectation: learned)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)

        client.send(.valueChanged(editedText: "Cloudflare"), sessionID: insertion.sessionID)
        client.send(.focusLost, sessionID: insertion.sessionID)
        client.send(.focusLost, sessionID: insertion.sessionID)

        await fulfillment(of: [learned], timeout: 1)
        let values = await recorder.values
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.original, "Cloud Flower")
        XCTAssertEqual(values.first?.final, "Cloudflare")
    }

    func testRecordingStartReturnsWithoutWaitingForLearning() async {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "Cloud Flower",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(
            insertionResult: .observable(insertion)
        )
        let learned = expectation(description: "learned")
        let recorder = LearnedTextRecorder(expectation: learned)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)
        client.send(.valueChanged(editedText: "Cloudflare"), sessionID: insertion.sessionID)

        tracker.finishForRecordingStart()
        XCTAssertFalse(tracker.hasActiveSession)

        await fulfillment(of: [learned], timeout: 1)
    }

    func testUnreadableFinalRangeDiscardsSession() async {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "Cloud Flower",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(
            insertionResult: .observable(insertion)
        )
        let recorder = LearnedTextRecorder(expectation: nil)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)
        client.send(.valueChanged(editedText: nil), sessionID: insertion.sessionID)

        tracker.finishForRecordingStart()
        try? await Task.sleep(for: .milliseconds(50))

        let values = await recorder.values
        XCTAssertTrue(values.isEmpty)
    }

    func testUnreadableBoundedSnapshotImmediatelyAbandonsSession() {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "Cloud Flower",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(insertionResult: .observable(insertion))
        let tracker = TextEditTracker(client: client) { _, _, _ in }
        tracker.begin(insertion)

        client.send(.valueChanged(editedText: nil), sessionID: insertion.sessionID)

        XCTAssertFalse(tracker.hasActiveSession)
    }

    func testQueuedCallbackFromStoppedSessionCannotFinishItsReplacement() async {
        let first = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "first",
            applicationBundleID: "com.example.editor"
        )
        let second = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "second",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(insertionResult: .observable(first))
        let learned = expectation(description: "only replacement session learns")
        let recorder = LearnedTextRecorder(expectation: learned)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }

        tracker.begin(first)
        let stoppedHandler = client.handler(for: first.sessionID)
        tracker.begin(second)
        stoppedHandler?(.valueChanged(editedText: "private stale text"))
        stoppedHandler?(.focusLost)

        XCTAssertTrue(tracker.hasActiveSession)
        client.send(.valueChanged(editedText: "second corrected"), sessionID: second.sessionID)
        client.send(.focusLost, sessionID: second.sessionID)

        await fulfillment(of: [learned], timeout: 1)
        let values = await recorder.values
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.original, "second")
        XCTAssertEqual(values.first?.final, "second corrected")
    }

    func testRecordingStartDiscardsWhenBoundedSnapshotIsNotImmediatelyAvailable() async {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "hello",
            applicationBundleID: "com.example.editor"
        )
        let client = FakeAccessibilityTextClient(insertionResult: .observable(insertion))
        let recorder = LearnedTextRecorder(expectation: nil)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)
        let clock = ContinuousClock()
        let start = clock.now

        tracker.finishForRecordingStart()

        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(20))
        XCTAssertFalse(tracker.hasActiveSession)
        client.handler(for: insertion.sessionID)?(.valueChanged(editedText: "hello world"))
        try? await Task.sleep(for: .milliseconds(30))
        let values = await recorder.values
        XCTAssertTrue(values.isEmpty)
    }
}

@MainActor
private final class FakeAccessibilityTextClient: AccessibilityTextClientProtocol {
    let insertionResult: AccessibilityInsertionAttempt
    let unobservedInsertionResult: AccessibilityInsertionAttempt
    private(set) var insertionObservationRequests: [Bool] = []
    private var eventHandlers: [UUID: (AccessibilityTrackingEvent) -> Void] = [:]
    private var stoppedHandlers: [UUID: (AccessibilityTrackingEvent) -> Void] = [:]

    init(
        insertionResult: AccessibilityInsertionAttempt,
        unobservedInsertionResult: AccessibilityInsertionAttempt = .insertedWithoutObservation
    ) {
        self.insertionResult = insertionResult
        self.unobservedInsertionResult = unobservedInsertionResult
    }

    func insert(text: String, observationEnabled: Bool) -> AccessibilityInsertionAttempt {
        insertionObservationRequests.append(observationEnabled)
        return observationEnabled ? insertionResult : unobservedInsertionResult
    }

    func observe(
        sessionID: UUID,
        handler: @escaping (AccessibilityTrackingEvent) -> Void
    ) -> Bool {
        eventHandlers[sessionID] = handler
        return true
    }

    func stopObserving(sessionID: UUID) {
        stoppedHandlers[sessionID] = eventHandlers[sessionID]
        eventHandlers[sessionID] = nil
    }

    func send(_ event: AccessibilityTrackingEvent, sessionID: UUID) {
        eventHandlers[sessionID]?(event)
    }

    func handler(for sessionID: UUID) -> ((AccessibilityTrackingEvent) -> Void)? {
        eventHandlers[sessionID] ?? stoppedHandlers[sessionID]
    }
}

private actor LearnedTextRecorder {
    struct Value {
        let original: String
        let final: String
        let bundleID: String
    }

    private(set) var values: [Value] = []
    private let expectation: XCTestExpectation?

    init(expectation: XCTestExpectation?) {
        self.expectation = expectation
    }

    func record(original: String, final: String, bundleID: String) {
        values.append(Value(original: original, final: final, bundleID: bundleID))
        expectation?.fulfill()
    }
}
