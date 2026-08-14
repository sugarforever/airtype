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

        let difference = finalTokens.map(\.value).difference(from: originalTokens.map(\.value))
        var removals = Set<Int>()
        var insertions = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removals.insert(offset)
            case .insert(let offset, _, _): insertions.insert(offset)
            }
        }

        let originalChangedCount = removals.count
        let finalChangedCount = insertions.count
        let changedRatio = Double(max(originalChangedCount, finalChangedCount))
            / Double(max(originalTokens.count, finalTokens.count))
        guard changedRatio <= rewriteThreshold else { return [] }

        var runs: [(old: Range<Int>, new: Range<Int>)] = []
        var oldIndex = 0
        var newIndex = 0
        var runStart: (old: Int, new: Int)?

        func finishRun() {
            guard let start = runStart else { return }
            runs.append((start.old..<oldIndex, start.new..<newIndex))
            runStart = nil
        }

        while oldIndex < originalTokens.count || newIndex < finalTokens.count {
            let removesCurrent = removals.contains(oldIndex)
            let insertsCurrent = insertions.contains(newIndex)
            if removesCurrent || insertsCurrent {
                if runStart == nil { runStart = (oldIndex, newIndex) }
                if removesCurrent { oldIndex += 1 }
                if insertsCurrent { newIndex += 1 }
                continue
            }

            finishRun()
            if oldIndex < originalTokens.count { oldIndex += 1 }
            if newIndex < finalTokens.count { newIndex += 1 }
        }
        finishRun()

        return runs.compactMap { run in
            makeHunk(
                original: original,
                final: final,
                originalTokens: originalTokens,
                finalTokens: finalTokens,
                oldRange: run.old,
                newRange: run.new
            )
        }
    }

    private func makeHunk(
        original: String,
        final: String,
        originalTokens: [Token],
        finalTokens: [Token],
        oldRange: Range<Int>,
        newRange: Range<Int>
    ) -> CorrectionHunk? {
        let originalFragment = fragment(
            in: original, tokens: originalTokens,
            lower: oldRange.lowerBound, upper: oldRange.upperBound
        )
        let replacementFragment = fragment(
            in: final, tokens: finalTokens,
            lower: newRange.lowerBound, upper: newRange.upperBound
        )
        let originalValue = originalFragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacementValue = replacementFragment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalValue.isEmpty || !replacementValue.isEmpty else { return nil }

        let sentenceRange = containingSentenceRange(in: final, around: replacementFragment.range.lowerBound)
        let before = bounded(String(final[sentenceRange.lowerBound..<replacementFragment.range.lowerBound]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let after = String(String(final[replacementFragment.range.upperBound..<sentenceRange.upperBound])
            .prefix(maximumContextCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CorrectionHunk(
            original: originalValue,
            replacement: replacementValue,
            contextBefore: before,
            contextAfter: after
        )
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
