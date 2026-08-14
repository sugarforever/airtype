import XCTest
@testable import CorrectionLearningCore

final class CorrectionSampleIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRecordsCompatibleCorrectionByIncrementingCount() {
        var index = CorrectionSampleIndex()
        let hunk = CorrectionHunk(
            original: "Cloud Flower",
            replacement: "Cloudflare",
            contextBefore: "Deploy with",
            contextAfter: "Workers"
        )

        index.record(hunk, at: now)
        index.record(hunk, at: now.addingTimeInterval(60))

        XCTAssertEqual(index.samples.count, 1)
        XCTAssertEqual(index.samples.first?.correctionCount, 2)
        XCTAssertEqual(index.samples.first?.lastCorrectedAt, now.addingTimeInterval(60))
    }

    func testKeepsDifferentContextualReplacementSeparate() {
        var index = CorrectionSampleIndex()
        index.record(CorrectionHunk(
            original: "苹果",
            replacement: "Apple",
            contextBefore: "iPhone 来自",
            contextAfter: "公司"
        ), at: now)
        index.record(CorrectionHunk(
            original: "苹果",
            replacement: "苹果",
            contextBefore: "我买了一个",
            contextAfter: "作为水果"
        ), at: now)

        XCTAssertEqual(index.samples.count, 2)
    }

    func testExactMatchRanksAheadOfContextOnlyCandidate() {
        let exact = sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            original: "Cloud Flower",
            replacement: "Cloudflare",
            before: "Deploy",
            after: "Workers"
        )
        let contextual = sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            original: "edge platform",
            replacement: "edge network",
            before: "Deploy",
            after: "Workers"
        )
        var index = CorrectionSampleIndex(samples: [contextual, exact])

        let results = index.retrieve(
            for: "Deploy Cloud Flower with Workers",
            limit: 5,
            tokenBudget: 300,
            timeBudget: .milliseconds(5),
            now: now
        )

        XCTAssertEqual(results.first?.replacement, "Cloudflare")
    }

    func testRetrievalRespectsCountAndTokenBudget() {
        let samples = (0..<10).map { position in
            sample(
                id: UUID(),
                original: "term\(position)",
                replacement: String(repeating: "replacement", count: 8),
                before: "shared context",
                after: "suffix"
            )
        }
        var index = CorrectionSampleIndex(samples: samples)

        let results = index.retrieve(
            for: "shared context term0 term1 term2 term3 term4 term5",
            limit: 5,
            tokenBudget: 80,
            timeBudget: .milliseconds(5),
            now: now
        )

        XCTAssertLessThanOrEqual(results.count, 5)
        XCTAssertLessThanOrEqual(results.reduce(0) { $0 + $1.estimatedTokenCount }, 80)
    }

    func testDoesNotFuzzyMatchShortChineseToken() {
        var index = CorrectionSampleIndex(samples: [sample(
            id: UUID(),
            original: "苹果",
            replacement: "Apple",
            before: "科技公司",
            after: "发布产品"
        )])

        let results = index.retrieve(
            for: "我今天买了苹朵水果",
            limit: 5,
            tokenBudget: 300,
            timeBudget: .milliseconds(5),
            now: now
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testEvictionRemovesOldSingleCorrectionNeverMatchedSample() {
        let old = sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            original: "old",
            replacement: "old fixed",
            createdAt: now.addingTimeInterval(-10_000)
        )
        let frequent = sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            original: "frequent",
            replacement: "frequent fixed",
            correctionCount: 4,
            createdAt: now.addingTimeInterval(-20_000)
        )
        let recent = sample(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            original: "recent",
            replacement: "recent fixed",
            createdAt: now
        )
        var index = CorrectionSampleIndex(samples: [old, frequent, recent])

        let evicted = index.evictIfNeeded(maximumCount: 2)

        XCTAssertEqual(evicted, [old.id])
        XCTAssertEqual(Set(index.samples.map(\.id)), Set([frequent.id, recent.id]))
    }

    func testRetrievalPerformanceWithOneThousandSamples() {
        let samples = (0..<1_000).map { position in
            sample(
                id: UUID(),
                original: "technical-term-\(position)",
                replacement: "TechnicalTerm\(position)",
                before: "deployment context",
                after: "service"
            )
        }
        var index = CorrectionSampleIndex(samples: samples)
        let clock = ContinuousClock()
        let start = clock.now

        let results = index.retrieve(
            for: "Use technical-term-777 in this deployment context",
            limit: 5,
            tokenBudget: 300,
            timeBudget: .milliseconds(5),
            now: now
        )

        let duration = start.duration(to: clock.now)
        print("1,000-sample correction lookup: \(duration)")
        XCTAssertEqual(results.first?.replacement, "TechnicalTerm777")
        XCTAssertLessThan(duration, .milliseconds(5))
    }

    private func sample(
        id: UUID,
        original: String,
        replacement: String,
        before: String = "",
        after: String = "",
        correctionCount: Int = 1,
        createdAt: Date? = nil
    ) -> CorrectionSample {
        CorrectionSample(
            id: id,
            original: original,
            replacement: replacement,
            normalizedOriginal: CorrectionSampleIndex.normalize(original),
            contextBefore: before,
            contextAfter: after,
            correctionCount: correctionCount,
            matchCount: 0,
            createdAt: createdAt ?? now,
            lastCorrectedAt: createdAt ?? now,
            lastMatchedAt: nil
        )
    }
}
