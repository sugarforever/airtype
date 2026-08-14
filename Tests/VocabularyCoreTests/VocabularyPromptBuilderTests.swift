import XCTest
@testable import VocabularyCore

final class VocabularyPromptBuilderTests: XCTestCase {
    func testTermsRenderAsDelimitedLocalVocabulary() {
        let section = VocabularyPromptBuilder().section(terms: ["Cloudflare", "小木头"])

        XCTAssertEqual(
            section,
            """
            LOCAL USER VOCABULARY:
            These are correct spellings of terms the user commonly uses. Use them only when they fit the spoken context.
            - Cloudflare
            - 小木头
            """
        )
    }

    func testNoTermsReturnsEmptySection() {
        XCTAssertEqual(VocabularyPromptBuilder().section(terms: []), "")
    }
}
