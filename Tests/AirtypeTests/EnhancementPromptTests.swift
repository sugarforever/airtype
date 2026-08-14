import XCTest
@testable import CorrectionLearningCore

final class EnhancementPromptTests: XCTestCase {
    func testNoExamplesPreservesBasePrompt() {
        XCTAssertEqual(
            EnhancementPromptBuilder().prompt(examples: []),
            EnhancementPromptBuilder.basePrompt
        )
    }

    func testExampleAddsDelimitedContextualCorrectionGuidance() {
        let example = CorrectionPromptExample(
            sampleID: UUID(),
            original: "Cloud Flower",
            replacement: "Cloudflare",
            contextBefore: "Deploy with",
            contextAfter: "Workers"
        )

        let prompt = EnhancementPromptBuilder().prompt(examples: [example])

        XCTAssertTrue(prompt.contains("LOCAL USER CORRECTION EXAMPLES"))
        XCTAssertTrue(prompt.contains("Original: Cloud Flower"))
        XCTAssertTrue(prompt.contains("Correction: Cloudflare"))
        XCTAssertTrue(prompt.contains("Context: Deploy with [correction] Workers"))
        XCTAssertTrue(prompt.contains("only when the current context matches"))
    }

    func testExamplesAreRenderedInRankedOrder() {
        let first = CorrectionPromptExample(
            sampleID: UUID(),
            original: "first wrong",
            replacement: "first right",
            contextBefore: "",
            contextAfter: ""
        )
        let second = CorrectionPromptExample(
            sampleID: UUID(),
            original: "second wrong",
            replacement: "second right",
            contextBefore: "",
            contextAfter: ""
        )

        let prompt = EnhancementPromptBuilder().prompt(examples: [first, second])

        XCTAssertLessThan(
            prompt.range(of: "Original: first wrong")!.lowerBound,
            prompt.range(of: "Original: second wrong")!.lowerBound
        )
    }
}
