import XCTest
@testable import CorrectionLearningCore

final class PrivacySafeDiagnosticsTests: XCTestCase {
    func testTextDiagnosticContainsOnlyMetadata() {
        let sensitiveText = "private sentinel transcription"

        let diagnostic = PrivacySafeDiagnostics.textEvent(
            label: "Transcription completed",
            characterCount: sensitiveText.count
        )

        XCTAssertEqual(diagnostic, "Transcription completed (30 characters)")
        XCTAssertFalse(diagnostic.contains(sensitiveText))
    }
}
