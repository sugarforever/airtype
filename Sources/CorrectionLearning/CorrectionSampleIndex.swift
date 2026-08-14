import Foundation
import NaturalLanguage

public struct CorrectionSampleIndex: Sendable {
    private struct RankedCandidate {
        let id: UUID
        let score: Int
        let correctionCount: Int
        let lastMatchedAt: Date?
    }

    private static let exactScore = 1_000
    private static let completeOriginalScore = 700
    private static let fuzzyOriginalScore = 500
    private static let contextScore = 100
    private static let minimumFuzzyContextTokenOverlap = 1
    private static let minimumContextTokenOverlap = 2
    private static let maximumRankedCandidateCount = 256
    private static let maximumLookupUTF16Units = 4_096
    private static let maximumFuzzyTokenUTF8Count = 64

    public private(set) var samples: [CorrectionSample]
    private var positionsByID: [UUID: Int] = [:]
    private var sampleIDsByOriginalToken: [String: Set<UUID>] = [:]
    private var sampleIDsByContextToken: [String: Set<UUID>] = [:]
    private var sampleIDsByNormalizedOriginal: [String: Set<UUID>] = [:]
    private var originalTokensByID: [UUID: Set<String>] = [:]
    private var contextTokensByID: [UUID: Set<String>] = [:]

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

    @discardableResult
    public mutating func record(_ hunk: CorrectionHunk, at date: Date) -> CorrectionSample {
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
            let sample = samples[position]
            rebuildIndexes()
            return sample
        } else {
            let sample = CorrectionSample(
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
            )
            samples.append(sample)
            rebuildIndexes()
            return sample
        }
    }

    public func retrieve(
        for text: String,
        limit: Int,
        tokenBudget: Int,
        timeBudget: Duration,
        now _: Date
    ) -> [CorrectionPromptExample] {
        guard timeBudget > .zero else { return [] }
        let clock = ContinuousClock()
        return retrieve(
            for: text,
            limit: limit,
            tokenBudget: tokenBudget,
            deadline: clock.now.advanced(by: timeBudget),
            clock: clock
        )
    }

    func retrieve(
        for text: String,
        limit: Int,
        tokenBudget: Int,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock = ContinuousClock()
    ) -> [CorrectionPromptExample] {
        guard limit > 0, tokenBudget > 0, clock.now < deadline else { return [] }

        let lookupText = Self.boundedLookupText(text)
        let normalizedText = Self.normalize(lookupText)
        guard clock.now < deadline,
              let inputTokens = Self.tokens(in: normalizedText, deadline: deadline, clock: clock),
              clock.now < deadline,
              let exactKeys = Self.exactLookupKeys(
                  in: lookupText,
                  deadline: deadline,
                  clock: clock
              )
        else { return [] }

        var scores: [UUID: Int] = [:]
        for key in exactKeys {
            guard clock.now < deadline else { return [] }
            let ids = sampleIDsByNormalizedOriginal[key] ?? []
            guard addBestContextualVariant(
                from: ids,
                inputTokens: inputTokens,
                baseScore: Self.exactScore,
                to: &scores,
                deadline: deadline,
                clock: clock
            ) else { return [] }
        }

        if scores.isEmpty {
            let originalPostings = inputTokens
                .compactMap { sampleIDsByOriginalToken[$0] }
                .sorted { $0.count < $1.count }
            let contextPostings = inputTokens
                .compactMap { sampleIDsByContextToken[$0] }
                .sorted { $0.count < $1.count }
            var seenCandidateIDs = Set<UUID>()

            candidateLoop: for posting in originalPostings + contextPostings {
                for id in posting where seenCandidateIDs.insert(id).inserted {
                    guard clock.now < deadline else { return [] }
                    guard seenCandidateIDs.count <= Self.maximumRankedCandidateCount else {
                        break candidateLoop
                    }
                    guard let position = positionsByID[id] else { continue }
                    let sample = samples[position]
                    let originalTokens = originalTokensByID[id] ?? []
                    let contextTokens = contextTokensByID[id] ?? []
                    let originalOverlap = inputTokens.intersection(originalTokens).count
                    let contextOverlap = inputTokens.intersection(contextTokens).count

                    if !sample.normalizedOriginal.isEmpty,
                       normalizedText.contains(sample.normalizedOriginal) {
                        scores[id] = Self.exactScore + contextOverlap
                    } else if !originalTokens.isEmpty,
                              originalOverlap == originalTokens.count {
                        scores[id] = Self.completeOriginalScore + contextOverlap
                    } else if contextOverlap >= Self.minimumFuzzyContextTokenOverlap,
                              Self.hasFuzzyOriginalMatch(
                        originalTokens: originalTokens,
                        inputTokens: inputTokens,
                        deadline: deadline,
                        clock: clock
                    ) {
                        scores[id] = Self.fuzzyOriginalScore + contextOverlap
                    } else if contextOverlap >= Self.minimumContextTokenOverlap {
                        scores[id] = Self.contextScore + contextOverlap
                    }
                }
            }

            guard let disambiguated = disambiguatingVariants(
                in: scores,
                inputTokens: inputTokens,
                deadline: deadline,
                clock: clock
            ) else { return [] }
            scores = disambiguated
        }

        guard clock.now < deadline else { return [] }
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
        guard clock.now < deadline else { return [] }

        var examples: [CorrectionPromptExample] = []
        var usedTokens = 0
        for candidate in ranked {
            guard clock.now < deadline else { return [] }
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
        }
        return clock.now < deadline ? examples : []
    }

    public mutating func recordMatches(ids: [UUID], at date: Date) {
        for id in Set(ids) {
            guard let position = positionsByID[id] else { continue }
            samples[position].matchCount += 1
            if let lastMatchedAt = samples[position].lastMatchedAt {
                samples[position].lastMatchedAt = max(lastMatchedAt, date)
            } else {
                samples[position].lastMatchedAt = date
            }
        }
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

    @discardableResult
    public mutating func remove(id: UUID) -> Bool {
        let oldCount = samples.count
        samples.removeAll { $0.id == id }
        if samples.count != oldCount {
            rebuildIndexes()
        }
        return samples.count != oldCount
    }

    public mutating func restore(_ sample: CorrectionSample) {
        guard !samples.contains(where: { $0.id == sample.id }) else { return }
        samples.append(sample)
        rebuildIndexes()
    }

    private func addBestContextualVariant(
        from ids: Set<UUID>,
        inputTokens: Set<String>,
        baseScore: Int,
        to scores: inout [UUID: Int],
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> Bool {
        guard !ids.isEmpty else { return true }
        if ids.count == 1, let id = ids.first {
            let overlap = inputTokens.intersection(contextTokensByID[id] ?? []).count
            scores[id] = max(scores[id] ?? 0, baseScore + overlap)
            return true
        }

        var bestID: UUID?
        var bestOverlap = -1
        var isTied = false
        for id in ids {
            guard clock.now < deadline else { return false }
            let overlap = inputTokens.intersection(contextTokensByID[id] ?? []).count
            if overlap > bestOverlap {
                bestID = id
                bestOverlap = overlap
                isTied = false
            } else if overlap == bestOverlap {
                isTied = true
            }
        }
        guard let bestID, bestOverlap > 0, !isTied else { return true }
        scores[bestID] = max(scores[bestID] ?? 0, baseScore + bestOverlap)
        return true
    }

    private func disambiguatingVariants(
        in scores: [UUID: Int],
        inputTokens: Set<String>,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> [UUID: Int]? {
        let grouped = Dictionary(grouping: scores.keys) { id in
            guard let position = positionsByID[id] else { return "" }
            return samples[position].normalizedOriginal
        }
        var result: [UUID: Int] = [:]
        for ids in grouped.values {
            guard clock.now < deadline else { return nil }
            if ids.count == 1, let id = ids.first, let score = scores[id] {
                result[id] = score
                continue
            }
            var bestID: UUID?
            var bestScore = Int.min
            var bestOverlap = Int.min
            var isTied = false
            for id in ids {
                guard clock.now < deadline else { return nil }
                guard let score = scores[id] else { continue }
                let overlap = inputTokens.intersection(contextTokensByID[id] ?? []).count
                if score > bestScore || (score == bestScore && overlap > bestOverlap) {
                    bestID = id
                    bestScore = score
                    bestOverlap = overlap
                    isTied = false
                } else if score == bestScore, overlap == bestOverlap {
                    isTied = true
                }
            }
            guard let bestID, !isTied else { continue }
            result[bestID] = bestScore
        }
        return result
    }

    private mutating func rebuildIndexes() {
        positionsByID.removeAll(keepingCapacity: true)
        sampleIDsByOriginalToken.removeAll(keepingCapacity: true)
        sampleIDsByContextToken.removeAll(keepingCapacity: true)
        sampleIDsByNormalizedOriginal.removeAll(keepingCapacity: true)
        originalTokensByID.removeAll(keepingCapacity: true)
        contextTokensByID.removeAll(keepingCapacity: true)
        for (position, sample) in samples.enumerated() {
            positionsByID[sample.id] = position
            if !sample.normalizedOriginal.isEmpty {
                sampleIDsByNormalizedOriginal[sample.normalizedOriginal, default: []]
                    .insert(sample.id)
            }
            let originalTokens = Set(Self.tokens(in: sample.normalizedOriginal))
            let contextTokens = Set(Self.tokens(in: [
                Self.normalize(sample.contextBefore),
                Self.normalize(sample.contextAfter)
            ].joined(separator: " ")))
            originalTokensByID[sample.id] = originalTokens
            contextTokensByID[sample.id] = contextTokens
            for token in originalTokens {
                sampleIDsByOriginalToken[token, default: []].insert(sample.id)
            }
            for token in contextTokens {
                sampleIDsByContextToken[token, default: []].insert(sample.id)
            }
        }
    }

    private static func hasFuzzyOriginalMatch(
        originalTokens: Set<String>,
        inputTokens: Set<String>,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> Bool {
        guard !originalTokens.isEmpty else { return false }
        for originalToken in originalTokens {
            guard clock.now < deadline else { return false }
            if inputTokens.contains(originalToken) { continue }
            guard isSafeFuzzyToken(originalToken) else { return false }
            let originalLength = originalToken.utf8.count
            let maximumDistance = originalLength >= 7 ? 2 : 1
            var matched = false
            for inputToken in inputTokens {
                guard clock.now < deadline else { return false }
                guard isSafeFuzzyToken(inputToken),
                      abs(inputToken.utf8.count - originalLength) <= maximumDistance
                else { continue }
                if boundedEditDistance(
                    inputToken,
                    originalToken,
                    maximum: maximumDistance
                ) <= maximumDistance {
                    matched = true
                    break
                }
            }
            if !matched { return false }
        }
        return true
    }

    private static func isSafeFuzzyToken(_ token: String) -> Bool {
        let byteCount = token.utf8.count
        return byteCount >= 4
            && byteCount <= maximumFuzzyTokenUTF8Count
            && token.unicodeScalars.allSatisfy {
            $0.isASCII && CharacterSet.alphanumerics.contains($0)
        }
    }

    private static func boundedLookupText(_ text: String) -> String {
        let utf16 = text.utf16
        guard let cutoff = utf16.index(
            utf16.startIndex,
            offsetBy: maximumLookupUTF16Units,
            limitedBy: utf16.endIndex
        ), cutoff != utf16.endIndex else {
            return text
        }

        let half = maximumLookupUTF16Units / 2
        let head = Array(utf16.prefix(half))
        let tail = Array(utf16.suffix(half))
        let boundary = Array(" zzzairtypelookupboundaryzzz ".utf16)
        return String(decoding: head + boundary + tail, as: UTF16.self)
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

    private static func tokens(
        in text: String,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> Set<String>? {
        guard clock.now < deadline else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result = Set<String>()
        var completed = true
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            guard clock.now < deadline else {
                completed = false
                return false
            }
            let token = normalize(String(text[range]))
            if !token.isEmpty { result.insert(token) }
            return true
        }
        return completed && clock.now < deadline ? result : nil
    }

    private static func exactLookupKeys(
        in text: String,
        deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) -> Set<String>? {
        guard clock.now < deadline else { return nil }
        let parts = text.split(whereSeparator: \.isWhitespace).map { part in
            normalize(String(part).trimmingCharacters(in: .punctuationCharacters))
        }.filter { !$0.isEmpty }
        guard clock.now < deadline else { return nil }
        var keys = Set<String>()
        for lower in parts.indices {
            let maximumUpper = min(parts.count, lower + 5)
            guard lower + 1 <= maximumUpper else { continue }
            for upper in (lower + 1)...maximumUpper {
                guard clock.now < deadline else { return nil }
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
