import Foundation

public struct EnhancementPromptBuilder: Sendable {
    public init() {}

    public func prompt(
        examples: [CorrectionPromptExample],
        vocabularySection: String
    ) -> String {
        var localSections: [String] = []
        if !vocabularySection.isEmpty {
            localSections.append(vocabularySection)
        }

        guard !examples.isEmpty else {
            guard !localSections.isEmpty else { return Self.basePrompt }
            return Self.basePrompt + "\n\n" + localSections.joined(separator: "\n\n")
        }

        let rendered = examples.enumerated().map { position, example in
            """
            \(position + 1).
            Original: \(example.original)
            Correction: \(example.replacement)
            Context: \(example.contextBefore) [correction] \(example.contextAfter)
            """
        }.joined(separator: "\n")

        localSections.append("""
        LOCAL USER CORRECTION EXAMPLES:
        These examples were learned from this user's local edits. Apply a correction only when the current context matches; do not treat it as a global replacement rule.

        \(rendered)
        """)

        return Self.basePrompt + "\n\n" + localSections.joined(separator: "\n\n")
    }

    public static let basePrompt = """
        You are a speech-to-text error corrector. Fix transcription errors while preserving the speaker's original words as much as possible.

        CORRECT these issues:
        - Misrecognized words due to pronunciation, accent, or background noise
        - Homophones: choose contextually correct form (your/you're, their/there/they're, its/it's)
        - Technical terms and proper nouns: use correct casing (react → React, ios → iOS, github → GitHub)
        - Numbers and dates: convert to numerals (twenty three → 23, december fifth → December 5th)
        - Missing punctuation and capitalization
        - Sentence boundaries: split run-on sentences properly
        - Immediate word stutters: remove duplicates (I I I think → I think, the the → the)

        DO NOT change:
        - Filler words (um, uh, like, you know) - keep them
        - Self-corrections (keep "Monday, no wait, Tuesday" exactly as spoken)
        - User's grammar or dialect (preserve "I seen him" if that's what they said)
        - Repeated phrases for emphasis (keep "I think, I think we should")
        - Word choices or sentence structure

        IMPORTANT:
        - When uncertain if something is an error or intentional, leave it unchanged
        - Be conservative - only fix clear transcription errors
        - Return ONLY the corrected text, nothing else
        """
}

/// Formats diagnostic metadata without retaining or rendering the underlying text.
public enum PrivacySafeDiagnostics {
    public static func textEvent(label: String, characterCount: Int) -> String {
        let safeCount = max(0, characterCount)
        let unit = safeCount == 1 ? "character" : "characters"
        return "\(label) (\(safeCount) \(unit))"
    }

    public static func errorEvent(label: String, error: any Error) -> String {
        "\(label) (\(String(reflecting: type(of: error))))"
    }
}
