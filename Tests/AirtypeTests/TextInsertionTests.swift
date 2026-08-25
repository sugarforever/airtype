#if canImport(Airtype)
import XCTest
@testable import Airtype

@MainActor
final class TextInsertionTests: XCTestCase {
    func testTrustedInsertionUsesPasteWithoutRequestingPermission() async throws {
        var requestedPermission = false
        var pastedText: String?
        let inserter = TextInserter(
            isAccessibilityTrusted: { true },
            requestAccessibilityTrust: {
                requestedPermission = true
                return true
            },
            paste: { pastedText = $0 }
        )

        try await inserter.insert(text: "Airtype")

        XCTAssertFalse(requestedPermission)
        XCTAssertEqual(pastedText, "Airtype")
    }

    func testDeniedPermissionDoesNotPaste() async {
        var pasted = false
        let inserter = TextInserter(
            isAccessibilityTrusted: { false },
            requestAccessibilityTrust: { false },
            paste: { _ in pasted = true }
        )

        do {
            try await inserter.insert(text: "Airtype")
            XCTFail("Expected permission denial")
        } catch {
            XCTAssertEqual(error as? TextInsertionError, .noAccessibilityPermission)
        }
        XCTAssertFalse(pasted)
    }

    func testPermissionGrantedAfterPromptContinuesToPaste() async throws {
        var pastedText: String?
        let inserter = TextInserter(
            isAccessibilityTrusted: { false },
            requestAccessibilityTrust: { true },
            paste: { pastedText = $0 }
        )

        try await inserter.insert(text: "Airtype")

        XCTAssertEqual(pastedText, "Airtype")
    }
}
#endif
