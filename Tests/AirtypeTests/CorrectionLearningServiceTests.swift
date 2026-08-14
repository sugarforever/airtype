import XCTest
@testable import CorrectionLearningCore

final class CorrectionLearningServiceTests: XCTestCase {
    func testLearnExtractsAndPersistsCorrection() async throws {
        let store = InMemoryCorrectionStore()
        let service = CorrectionLearningService(store: store)

        await service.learn(
            original: "Deploy Cloud Flower today.",
            final: "Deploy Cloudflare today.",
            applicationBundleID: "com.example.editor"
        )

        let samples = try store.loadSamples()
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.original, "Cloud Flower")
        XCTAssertEqual(samples.first?.replacement, "Cloudflare")
        XCTAssertEqual(try store.loadSessions().first?.status, .learned)
    }

    func testExamplesReturnRelevantSampleAndPersistMatchStatistics() async throws {
        let store = InMemoryCorrectionStore(samples: [sample()])
        let service = CorrectionLearningService(store: store)

        let examples = await service.examples(for: "Deploy Cloud Flower again")

        XCTAssertEqual(examples.first?.replacement, "Cloudflare")
        XCTAssertEqual(try store.loadSamples().first?.matchCount, 1)
        XCTAssertNotNil(try store.loadSamples().first?.lastMatchedAt)
    }

    func testDeleteRemovesSampleFromBrowseAndEnhancementRetrieval() async throws {
        let store = InMemoryCorrectionStore()
        let service = CorrectionLearningService(store: store)
        await service.learn(
            original: "Deploy Cloud Flower today.",
            final: "Deploy Cloudflare today.",
            applicationBundleID: "test"
        )
        let learnedSamples = await service.samples()
        let id = try XCTUnwrap(learnedSamples.first?.id)

        try await service.deleteSample(id: id)

        let samplesAfterDeletion = await service.samples()
        let examplesAfterDeletion = await service.examples(for: "Cloud Flower")
        XCTAssertTrue(samplesAfterDeletion.isEmpty)
        XCTAssertTrue(examplesAfterDeletion.isEmpty)
        XCTAssertTrue(try store.loadSamples().isEmpty)
    }

    func testBrowseOrdersSamplesByMostRecentlyCorrected() async {
        let older = sample(lastCorrectedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = sample(
            original: "Workers",
            replacement: "Cloudflare Workers",
            lastCorrectedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let service = CorrectionLearningService(store: InMemoryCorrectionStore(samples: [older, newer]))

        let samples = await service.samples()

        XCTAssertEqual(samples.map(\.id), [newer.id, older.id])
    }

    func testDeleteRestoresSampleWhenPersistenceFails() async throws {
        let storedSample = sample()
        let service = CorrectionLearningService(
            store: DeleteFailingCorrectionStore(samples: [storedSample])
        )

        do {
            try await service.deleteSample(id: storedSample.id)
            XCTFail("Expected deleting a sample to surface the persistence failure")
        } catch {
            // The service restores the in-memory sample when local persistence fails.
        }

        let samplesAfterFailure = await service.samples()
        let examplesAfterFailure = await service.examples(for: "Cloud Flower")
        XCTAssertEqual(samplesAfterFailure, [storedSample])
        XCTAssertEqual(examplesAfterFailure.first?.sampleID, storedSample.id)
    }

    func testStoreFailureDoesNotEscapeIntoLearningCall() async {
        let service = CorrectionLearningService(store: FailingCorrectionStore())

        await service.learn(
            original: "Use Cloud Flower.",
            final: "Use Cloudflare.",
            applicationBundleID: "com.example.editor"
        )
        let examples = await service.examples(for: "Cloud Flower")

        XCTAssertTrue(examples.isEmpty)
    }

    func testRewriteRecordsDiscardedSessionWithoutSample() async throws {
        let store = InMemoryCorrectionStore()
        let service = CorrectionLearningService(store: store)

        await service.learn(
            original: "alpha beta gamma delta",
            final: "completely unrelated replacement",
            applicationBundleID: "com.example.editor"
        )

        XCTAssertTrue(try store.loadSamples().isEmpty)
        XCTAssertEqual(try store.loadSessions().first?.status, .discarded)
    }

    private func sample(
        original: String = "Cloud Flower",
        replacement: String = "Cloudflare",
        lastCorrectedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> CorrectionSample {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return CorrectionSample(
            id: UUID(),
            original: original,
            replacement: replacement,
            normalizedOriginal: CorrectionSampleIndex.normalize(original),
            contextBefore: "Deploy",
            contextAfter: "today",
            correctionCount: 1,
            matchCount: 0,
            createdAt: date,
            lastCorrectedAt: lastCorrectedAt,
            lastMatchedAt: nil
        )
    }
}

private final class InMemoryCorrectionStore: CorrectionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [CorrectionSample]
    private var sessions: [EditSessionMetadata] = []

    init(samples: [CorrectionSample] = []) {
        self.samples = samples
    }

    func loadSamples() throws -> [CorrectionSample] {
        lock.withLock { samples }
    }

    func upsert(sample: CorrectionSample) throws {
        lock.withLock {
            samples.removeAll { $0.id == sample.id }
            samples.append(sample)
        }
    }

    func deleteSamples(ids: [UUID]) throws {
        lock.withLock { samples.removeAll { ids.contains($0.id) } }
    }

    func recordSession(_ session: EditSessionMetadata) throws {
        lock.withLock { sessions.append(session) }
    }

    func loadSessions() throws -> [EditSessionMetadata] {
        lock.withLock { sessions }
    }

    func markMatched(ids: [UUID], at date: Date) throws {
        lock.withLock {
            for position in samples.indices where ids.contains(samples[position].id) {
                samples[position].matchCount += 1
                samples[position].lastMatchedAt = date
            }
        }
    }
}

private struct FailingCorrectionStore: CorrectionStoring {
    struct Failure: Error {}
    func loadSamples() throws -> [CorrectionSample] { throw Failure() }
    func upsert(sample: CorrectionSample) throws { throw Failure() }
    func deleteSamples(ids: [UUID]) throws { throw Failure() }
    func recordSession(_ session: EditSessionMetadata) throws { throw Failure() }
    func loadSessions() throws -> [EditSessionMetadata] { throw Failure() }
    func markMatched(ids: [UUID], at date: Date) throws { throw Failure() }
}

private struct DeleteFailingCorrectionStore: CorrectionStoring {
    struct Failure: Error {}
    private let samples: [CorrectionSample]

    init(samples: [CorrectionSample]) {
        self.samples = samples
    }

    func loadSamples() throws -> [CorrectionSample] { samples }
    func upsert(sample: CorrectionSample) throws {}
    func deleteSamples(ids: [UUID]) throws { throw Failure() }
    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { [] }
    func markMatched(ids: [UUID], at date: Date) throws {}
}
