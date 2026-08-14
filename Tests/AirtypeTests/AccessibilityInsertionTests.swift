import XCTest
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

        let result = try await coordinator.insert(text: "hello")

        guard case .accessibility(let insertion) = result else {
            return XCTFail("Expected observable Accessibility insertion")
        }
        XCTAssertEqual(insertion.originalText, "hello")
        XCTAssertFalse(pasted)
    }

    func testUnobservableAXInsertionDoesNotCreateTrackingSession() async throws {
        let client = FakeAccessibilityTextClient(insertionResult: .insertedWithoutObservation)
        let coordinator = TextInsertionCoordinator(client: client) { _ in }

        let result = try await coordinator.insert(text: "hello")

        XCTAssertEqual(result, .accessibilityWithoutObservation)
    }

    func testUnsupportedAXInsertionFallsBackToPaste() async throws {
        let client = FakeAccessibilityTextClient(insertionResult: .unsupported)
        var pastedText: String?
        let coordinator = TextInsertionCoordinator(client: client) { pastedText = $0 }

        let result = try await coordinator.insert(text: "hello")

        XCTAssertEqual(result, .paste)
        XCTAssertEqual(pastedText, "hello")
    }

    func testPermissionFailureDoesNotPaste() async {
        let client = FakeAccessibilityTextClient(insertionResult: .permissionDenied)
        var pasted = false
        let coordinator = TextInsertionCoordinator(client: client) { _ in pasted = true }

        do {
            _ = try await coordinator.insert(text: "hello")
            XCTFail("Expected permission error")
        } catch {
            XCTAssertEqual(error as? AccessibilityTextError, .permissionDenied)
            XCTAssertFalse(pasted)
        }
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
            insertionResult: .observable(insertion),
            finalText: "Cloudflare"
        )
        let learned = expectation(description: "learned")
        let recorder = LearnedTextRecorder(expectation: learned)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)

        client.send(.valueChanged, sessionID: insertion.sessionID)
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
            insertionResult: .observable(insertion),
            finalText: "Cloudflare"
        )
        let learned = expectation(description: "learned")
        let recorder = LearnedTextRecorder(expectation: learned)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)
        client.send(.valueChanged, sessionID: insertion.sessionID)

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
            insertionResult: .observable(insertion),
            finalText: nil
        )
        let recorder = LearnedTextRecorder(expectation: nil)
        let tracker = TextEditTracker(client: client) { original, final, bundleID in
            await recorder.record(original: original, final: final, bundleID: bundleID)
        }
        tracker.begin(insertion)
        client.send(.valueChanged, sessionID: insertion.sessionID)

        tracker.finishForRecordingStart()
        try? await Task.sleep(for: .milliseconds(50))

        let values = await recorder.values
        XCTAssertTrue(values.isEmpty)
    }
}

@MainActor
private final class FakeAccessibilityTextClient: AccessibilityTextClientProtocol {
    let insertionResult: AccessibilityInsertionAttempt
    var finalText: String?
    private var eventHandlers: [UUID: (AccessibilityTrackingEvent) -> Void] = [:]

    init(insertionResult: AccessibilityInsertionAttempt, finalText: String? = nil) {
        self.insertionResult = insertionResult
        self.finalText = finalText
    }

    func insert(text: String) -> AccessibilityInsertionAttempt { insertionResult }

    func observe(
        sessionID: UUID,
        handler: @escaping (AccessibilityTrackingEvent) -> Void
    ) -> Bool {
        eventHandlers[sessionID] = handler
        return true
    }

    func stopObserving(sessionID: UUID) {
        eventHandlers[sessionID] = nil
    }

    func editedText(sessionID: UUID) -> String? { finalText }

    func send(_ event: AccessibilityTrackingEvent, sessionID: UUID) {
        eventHandlers[sessionID]?(event)
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
