import Foundation
import NaturalLanguage

public struct CorrectionSampleIndex: Sendable {
    private struct RankedCandidate {
        let id: UUID
        let score: Int
        let correctionCount: Int
        let lastMatchedAt: Date?
    }

    public private(set) var samples: [CorrectionSample]
    private var positionsByID: [UUID: Int] = [:]
    private var sampleIDsByToken: [String: Set<UUID>] = [:]
    private var sampleIDsByNormalizedOriginal: [String: Set<UUID>] = [:]

    public init(samples: [CorrectionSample] = []) {
        self.samples = samples
        rebuildIndexes()
    }

    public static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public mutating func record(_ hunk: CorrectionHunk, at date: Date) {
        let normalizedOriginal = Self.normalize(hunk.original)
        let normalizedReplacement = Self.normalize(hunk.replacement)
        let normalizedBefore = Self.normalize(hunk.contextBefore)
        let normalizedAfter = Self.normalize(hunk.contextAfter)

        if let position = samples.firstIndex(where: {
            $0.normalizedOriginal == normalizedOriginal
                && Self.normalize($0.replacement) == normalizedReplacement
                && Self.normalize($0.contextBefore) == normalizedBefore
                && Self.normalize($0.contextAfter) == normalizedAfter
        }) {
            samples[position].correctionCount += 1
            samples[position].lastCorrectedAt = date
        } else {
            samples.append(CorrectionSample(
                id: UUID(),
                original: hunk.original,
                replacement: hunk.replacement,
                normalizedOriginal: normalizedOriginal,
                contextBefore: hunk.contextBefore,
                contextAfter: hunk.contextAfter,
                correctionCount: 1,
                matchCount: 0,
                createdAt: date,
                lastCorrectedAt: date,
                lastMatchedAt: nil
            ))
        }
        rebuildIndexes()
    }

    public mutating func retrieve(
        for text: String,
        limit: Int,
        tokenBudget: Int,
        timeBudget: Duration,
        now: Date
    ) -> [CorrectionPromptExample] {
        guard limit > 0, tokenBudget > 0 else { return [] }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeBudget)
        let normalizedText = Self.normalize(text)
        let inputTokens = Set(Self.tokens(in: normalizedText))
        var scores: [UUID: Int] = [:]
        for key in Self.exactLookupKeys(in: text) {
            for id in sampleIDsByNormalizedOriginal[key] ?? [] {
                scores[id] = 1_000
            }
        }
        let postings = inputTokens
            .compactMap { sampleIDsByToken[$0] }
            .sorted { $0.count < $1.count }
        var seenCandidateIDs = Set<UUID>()
        if scores.isEmpty {
            candidateLoop: for posting in postings {
                for id in posting where seenCandidateIDs.insert(id).inserted {
                    guard clock.now < deadline, let position = positionsByID[id] else {
                        break candidateLoop
                    }
                    let sample = samples[position]
                    if !sample.normalizedOriginal.isEmpty,
                       normalizedText.contains(sample.normalizedOriginal) {
                        scores[id] = 1_000
                    } else {
                        let overlap = inputTokens.intersection(Self.tokensForIndex(sample)).count
                        scores[id] = overlap * 10
                    }
                }
            }
        }

        if clock.now < deadline {
            let candidateIDs = Set(scores.keys)
            for id in candidateIDs {
                guard clock.now < deadline, let position = positionsByID[id] else { break }
                let sample = samples[position]
                let term = sample.normalizedOriginal
                guard term.count >= 4 else { continue }
                for token in inputTokens where abs(token.count - term.count) <= 2 {
                    if Self.boundedEditDistance(token, term, maximum: 2) <= 2 {
                        scores[id, default: 0] += 5
                        break
                    }
                }
            }
        }

        let ranked = scores.compactMap { id, score -> RankedCandidate? in
            guard let position = positionsByID[id] else { return nil }
            let sample = samples[position]
            return RankedCandidate(
                id: id,
                score: score,
                correctionCount: sample.correctionCount,
                lastMatchedAt: sample.lastMatchedAt
            )
        }.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.correctionCount != $1.correctionCount {
                return $0.correctionCount > $1.correctionCount
            }
            if $0.lastMatchedAt != $1.lastMatchedAt {
                return ($0.lastMatchedAt ?? .distantPast) > ($1.lastMatchedAt ?? .distantPast)
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        var examples: [CorrectionPromptExample] = []
        var usedTokens = 0
        for candidate in ranked {
            guard examples.count < limit,
                  let position = positionsByID[candidate.id] else { break }
            let sample = samples[position]
            let example = CorrectionPromptExample(
                sampleID: sample.id,
                original: sample.original,
                replacement: sample.replacement,
                contextBefore: sample.contextBefore,
                contextAfter: sample.contextAfter
            )
            guard usedTokens + example.estimatedTokenCount <= tokenBudget else { continue }
            examples.append(example)
            usedTokens += example.estimatedTokenCount
            samples[position].matchCount += 1
            samples[position].lastMatchedAt = now
        }
        return examples
    }

    @discardableResult
    public mutating func evictIfNeeded(maximumCount: Int) -> [UUID] {
        guard samples.count > maximumCount else { return [] }
        let removalCount = samples.count - max(0, maximumCount)
        let sorted = samples.sorted {
            if $0.correctionCount != $1.correctionCount {
                return $0.correctionCount < $1.correctionCount
            }
            if ($0.lastMatchedAt == nil) != ($1.lastMatchedAt == nil) {
                return $0.lastMatchedAt == nil
            }
            let leftActivity = $0.lastMatchedAt ?? $0.createdAt
            let rightActivity = $1.lastMatchedAt ?? $1.createdAt
            if leftActivity != rightActivity { return leftActivity < rightActivity }
            return $0.id.uuidString < $1.id.uuidString
        }
        let removedIDs = sorted.prefix(removalCount).map(\.id)
        let removedSet = Set(removedIDs)
        samples.removeAll { removedSet.contains($0.id) }
        rebuildIndexes()
        return removedIDs
    }

    private mutating func rebuildIndexes() {
        positionsByID.removeAll(keepingCapacity: true)
        sampleIDsByToken.removeAll(keepingCapacity: true)
        sampleIDsByNormalizedOriginal.removeAll(keepingCapacity: true)
        for (position, sample) in samples.enumerated() {
            positionsByID[sample.id] = position
            if !sample.normalizedOriginal.isEmpty {
                sampleIDsByNormalizedOriginal[sample.normalizedOriginal, default: []]
                    .insert(sample.id)
            }
            for token in Self.tokensForIndex(sample) {
                sampleIDsByToken[token, default: []].insert(sample.id)
            }
        }
    }

    private static func tokensForIndex(_ sample: CorrectionSample) -> Set<String> {
        Set(tokens(in: [
            sample.normalizedOriginal,
            normalize(sample.contextBefore),
            normalize(sample.contextAfter)
        ].joined(separator: " ")))
    }

    private static func tokens(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = normalize(String(text[range]))
            if !token.isEmpty { result.append(token) }
            return true
        }
        return result
    }

    private static func exactLookupKeys(in text: String) -> Set<String> {
        let parts = text.split(whereSeparator: \.isWhitespace).map { part in
            normalize(String(part).trimmingCharacters(in: .punctuationCharacters))
        }.filter { !$0.isEmpty }
        var keys = Set<String>()
        for lower in parts.indices {
            let maximumUpper = min(parts.count, lower + 5)
            for upper in (lower + 1)...maximumUpper {
                keys.insert(parts[lower..<upper].joined(separator: " "))
            }
        }
        return keys
    }

    private static func boundedEditDistance(
        _ lhs: String,
        _ rhs: String,
        maximum: Int
    ) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= maximum else { return maximum + 1 }
        var previous = Array(0...right.count)
        for (leftOffset, leftCharacter) in left.enumerated() {
            var current = [leftOffset + 1]
            var rowMinimum = current[0]
            for (rightOffset, rightCharacter) in right.enumerated() {
                let value = min(
                    current[rightOffset] + 1,
                    previous[rightOffset + 1] + 1,
                    previous[rightOffset] + (leftCharacter == rightCharacter ? 0 : 1)
                )
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > maximum { return maximum + 1 }
            previous = current
        }
        return previous[right.count]
    }
}
