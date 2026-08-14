import XCTest
@testable import CorrectionLearningCore

final class CorrectionLearningFlowTests: XCTestCase {
    func testEnabledObservableInsertionReturnsSessionToTrack() {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "hello",
            applicationBundleID: "com.example.editor"
        )

        let result = CorrectionLearningFlow.insertionToTrack(
            learningEnabled: true,
            outcome: .accessibility(insertion)
        )

        XCTAssertEqual(result, insertion)
    }

    func testDisabledLearningNeverReturnsSession() {
        let insertion = AccessibilityInsertion(
            sessionID: UUID(),
            originalText: "hello",
            applicationBundleID: "com.example.editor"
        )

        XCTAssertNil(CorrectionLearningFlow.insertionToTrack(
            learningEnabled: false,
            outcome: .accessibility(insertion)
        ))
    }

    func testPasteInsertionNeverReturnsSession() {
        XCTAssertNil(CorrectionLearningFlow.insertionToTrack(
            learningEnabled: true,
            outcome: .paste
        ))
    }

    func testUnobservableAXInsertionNeverReturnsSession() {
        XCTAssertNil(CorrectionLearningFlow.insertionToTrack(
            learningEnabled: true,
            outcome: .accessibilityWithoutObservation
        ))
    }
}
