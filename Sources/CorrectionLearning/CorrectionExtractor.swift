import Foundation
import NaturalLanguage

public struct CorrectionExtractor: CorrectionExtracting {
    private struct Token {
        let value: String
        let range: Range<String.Index>
    }

    public let rewriteThreshold: Double
    public let maximumContextCharacters: Int

    public init(
        rewriteThreshold: Double = 0.5,
        maximumContextCharacters: Int = 400
    ) {
        self.rewriteThreshold = rewriteThreshold
        self.maximumContextCharacters = maximumContextCharacters
    }

    public func extract(original: String, final: String) -> [CorrectionHunk] {
        guard original != final, !original.isEmpty, !final.isEmpty else { return [] }

        let originalTokens = tokens(in: original)
        let finalTokens = tokens(in: final)
        guard !originalTokens.isEmpty, !finalTokens.isEmpty else { return [] }

        var prefixCount = 0
        while prefixCount < min(originalTokens.count, finalTokens.count),
              originalTokens[prefixCount].value == finalTokens[prefixCount].value {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < min(originalTokens.count, finalTokens.count) - prefixCount,
              originalTokens[originalTokens.count - suffixCount - 1].value
                == finalTokens[finalTokens.count - suffixCount - 1].value {
            suffixCount += 1
        }

        let originalChangedCount = originalTokens.count - prefixCount - suffixCount
        let finalChangedCount = finalTokens.count - prefixCount - suffixCount
        let changedRatio = Double(max(originalChangedCount, finalChangedCount))
            / Double(max(originalTokens.count, finalTokens.count))
        guard changedRatio <= rewriteThreshold else { return [] }

        let originalFragment = fragment(
            in: original,
            tokens: originalTokens,
            lower: prefixCount,
            upper: originalTokens.count - suffixCount
        )
        let replacementFragment = fragment(
            in: final,
            tokens: finalTokens,
            lower: prefixCount,
            upper: finalTokens.count - suffixCount
        )

        let originalValue = originalFragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementValue = replacementFragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalValue.isEmpty || !replacementValue.isEmpty else { return [] }

        let sentenceRange = containingSentenceRange(
            in: final,
            around: replacementFragment.range.lowerBound
        )
        let before = bounded(String(final[sentenceRange.lowerBound..<replacementFragment.range.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let after = bounded(String(final[replacementFragment.range.upperBound..<sentenceRange.upperBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return [CorrectionHunk(
            original: originalValue,
            replacement: replacementValue,
            contextBefore: before,
            contextAfter: after
        )]
    }

    private func tokens(in text: String) -> [Token] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var wordRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            wordRanges.append(range)
            return true
        }

        var result: [Token] = []
        var cursor = text.startIndex
        for range in wordRanges {
            appendNonWhitespaceTokens(in: text, range: cursor..<range.lowerBound, to: &result)
            result.append(Token(value: String(text[range]), range: range))
            cursor = range.upperBound
        }
        appendNonWhitespaceTokens(in: text, range: cursor..<text.endIndex, to: &result)
        return result
    }

    private func appendNonWhitespaceTokens(
        in text: String,
        range: Range<String.Index>,
        to result: inout [Token]
    ) {
        var index = range.lowerBound
        while index < range.upperBound {
            let next = text.index(after: index)
            let value = String(text[index..<next])
            if !value.allSatisfy(\.isWhitespace) {
                result.append(Token(value: value, range: index..<next))
            }
            index = next
        }
    }

    private func fragment(
        in text: String,
        tokens: [Token],
        lower: Int,
        upper: Int
    ) -> (text: String, range: Range<String.Index>) {
        if lower < upper {
            let range = tokens[lower].range.lowerBound..<tokens[upper - 1].range.upperBound
            return (String(text[range]), range)
        }

        let insertionPoint: String.Index
        if lower < tokens.count {
            insertionPoint = tokens[lower].range.lowerBound
        } else {
            insertionPoint = text.endIndex
        }
        return ("", insertionPoint..<insertionPoint)
    }

    private func containingSentenceRange(
        in text: String,
        around index: String.Index
    ) -> Range<String.Index> {
        guard !text.isEmpty else { return text.startIndex..<text.endIndex }
        let probe = index == text.endIndex ? text.index(before: index) : index
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        return tokenizer.tokenRange(at: probe)
    }

    private func bounded(_ value: String) -> String {
        guard value.count > maximumContextCharacters else { return value }
        return String(value.suffix(maximumContextCharacters))
    }
}
