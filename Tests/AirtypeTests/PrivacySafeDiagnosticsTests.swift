import XCTest
@testable import CorrectionLearningCore
#if canImport(Airtype) && DEBUG
@testable import Airtype
#endif

final class PrivacySafeDiagnosticsTests: XCTestCase {
#if canImport(Airtype) && DEBUG
    func testLocalASRDiagnosticsOmitSensitiveFieldsUnlessEnabled() {
        XCTAssertNil(LocalASRDiagnostics.line(
            event: "request", fields: ["context": "private vocabulary"], enabled: false
        ))
    }

    func testLocalASRDiagnosticsPreserveExactContextWithoutLogLineInjection() throws {
        let context = "小木头, VerySmallWoods, Claude, Anthropic, Codex\n\"test\""
        let line = try XCTUnwrap(LocalASRDiagnostics.line(
            event: "request", fields: ["context": context, "request_id": "test-request"], enabled: true
        ))
        XCTAssertFalse(line.contains("\n"))
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(decoded["event"] as? String, "request")
        let fields = try XCTUnwrap(decoded["fields"] as? [String: String])
        XCTAssertEqual(fields["context"], context)
        XCTAssertEqual(fields["request_id"], "test-request")
    }
#endif

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
