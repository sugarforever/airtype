import XCTest
@testable import CorrectionLearningCore

final class EnhancementPromptTests: XCTestCase {
    func testSmartRewritePromptTreatsSpeechCorrectionsAsInstructionsInsteadOfOutput() {
        let prompt = EnhancementPromptBuilder().prompt(
            mode: .smartRewrite,
            examples: [],
            vocabularySection: ""
        )

        XCTAssertTrue(prompt.contains("Keep only the speaker's final decision"))
        XCTAssertTrue(prompt.contains("Remove filler words"))
        XCTAssertTrue(prompt.contains("Reorganize out-of-order thoughts"))
        XCTAssertTrue(prompt.contains("Do not invent facts"))
        XCTAssertFalse(prompt.contains("keep \"Monday, no wait, Tuesday\" exactly as spoken"))
    }

    func testProofreadPromptRemainsConservative() {
        let prompt = EnhancementPromptBuilder().prompt(
            mode: .proofread,
            examples: [],
            vocabularySection: ""
        )

        XCTAssertEqual(prompt, EnhancementPromptBuilder.basePrompt)
    }

    func testNoTermsAndNoExamplesPreserveExactBasePrompt() {
        XCTAssertEqual(
            EnhancementPromptBuilder().prompt(examples: [], vocabularySection: ""),
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

        let prompt = EnhancementPromptBuilder().prompt(
            examples: [example],
            vocabularySection: ""
        )

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

        let prompt = EnhancementPromptBuilder().prompt(
            examples: [first, second],
            vocabularySection: ""
        )

        XCTAssertLessThan(
            prompt.range(of: "Original: first wrong")!.lowerBound,
            prompt.range(of: "Original: second wrong")!.lowerBound
        )
    }

    func testVocabularyAppearsBeforeContextualCorrectionExamples() {
        let example = CorrectionPromptExample(
            sampleID: UUID(),
            original: "Cloud Flower",
            replacement: "Cloudflare",
            contextBefore: "",
            contextAfter: ""
        )

        let prompt = EnhancementPromptBuilder().prompt(
            examples: [example],
            vocabularySection: "LOCAL USER VOCABULARY:\n- Cloudflare"
        )

        XCTAssertLessThan(
            prompt.range(of: "LOCAL USER VOCABULARY")!.lowerBound,
            prompt.range(of: "LOCAL USER CORRECTION EXAMPLES")!.lowerBound
        )
    }
}
