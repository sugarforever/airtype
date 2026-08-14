import XCTest
@testable import CorrectionLearningCore

final class CorrectionExtractorTests: XCTestCase {
    func testExtractsEnglishPhraseReplacementWithSentenceContext() {
        let result = CorrectionExtractor().extract(
            original: "Today we deploy with Cloud Flower.",
            final: "Today we deploy with Cloudflare."
        )

        XCTAssertEqual(result, [
            CorrectionHunk(
                original: "Cloud Flower",
                replacement: "Cloudflare",
                contextBefore: "Today we deploy with",
                contextAfter: "."
            )
        ])
    }

    func testExtractsChineseWordReplacement() {
        let result = CorrectionExtractor().extract(
            original: "我们使用瑞艾克特开发应用。",
            final: "我们使用 React 开发应用。"
        )

        XCTAssertEqual(result.first?.replacement, "React")
        XCTAssertEqual(result.first?.contextAfter, "开发应用。")
    }

    func testRejectsLargeRewrite() {
        let result = CorrectionExtractor().extract(
            original: "alpha beta gamma delta",
            final: "completely unrelated replacement"
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testExtractsInsertedWord() {
        let result = CorrectionExtractor().extract(
            original: "Deploy now.",
            final: "Deploy Cloudflare now."
        )

        XCTAssertEqual(result, [
            CorrectionHunk(
                original: "",
                replacement: "Cloudflare",
                contextBefore: "Deploy",
                contextAfter: "now."
            )
        ])
    }

    func testExtractsDeletedWord() {
        let result = CorrectionExtractor().extract(
            original: "Use Cloud Flower today.",
            final: "Use Cloud today."
        )

        XCTAssertEqual(result.first?.original, "Flower")
        XCTAssertEqual(result.first?.replacement, "")
    }

    func testExtractsPunctuationCorrection() {
        let result = CorrectionExtractor().extract(
            original: "Hello world.",
            final: "Hello, world."
        )

        XCTAssertEqual(result.first?.original, "")
        XCTAssertEqual(result.first?.replacement, ",")
    }

    func testIdenticalTextProducesNoCorrections() {
        XCTAssertTrue(CorrectionExtractor().extract(
            original: "No changes.",
            final: "No changes."
        ).isEmpty)
    }

    func testCompleteDeletionProducesNoCorrections() {
        XCTAssertTrue(CorrectionExtractor().extract(
            original: "Delete everything.",
            final: ""
        ).isEmpty)
    }

    func testBoundsLongSentenceContext() {
        let prefix = String(repeating: "context ", count: 100)
        let result = CorrectionExtractor(maximumContextCharacters: 40).extract(
            original: prefix + "Cloud Flower.",
            final: prefix + "Cloudflare."
        )

        XCTAssertLessThanOrEqual(result.first?.contextBefore.count ?? .max, 40)
    }

    func testSeparatesDistantCorrectionsIntoIndependentHunks() {
        let result = CorrectionExtractor().extract(
            original: "Use Cloud Flower for the service and React Native for the app.",
            final: "Use Cloudflare for the service and ReactNative for the app."
        )

        XCTAssertEqual(result.map(\.original), ["Cloud Flower", "React Native"])
        XCTAssertEqual(result.map(\.replacement), ["Cloudflare", "ReactNative"])
    }
}
