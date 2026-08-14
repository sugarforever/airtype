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
        for _ in 0..<100 {
            if try store.loadSamples().first?.matchCount == 1 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(try store.loadSamples().first?.matchCount, 1)
        XCTAssertNotNil(try store.loadSamples().first?.lastMatchedAt)
    }

    func testExamplesReturnWhileLearningExtractionIsBlocked() async {
        let started = expectation(description: "learning extraction started")
        let extractor = BlockingCorrectionExtractor(started: started)
        let seeded = sample()
        let service = CorrectionLearningService(
            store: InMemoryCorrectionStore(samples: [seeded]),
            extractor: extractor
        )
        let learningTask = Task {
            await service.learn(
                original: "blocked original",
                final: "blocked final",
                applicationBundleID: "com.example.editor"
            )
        }
        await fulfillment(of: [started], timeout: 1)
        Task.detached {
            try? await Task.sleep(for: .milliseconds(200))
            extractor.release()
        }
        let clock = ContinuousClock()
        let start = clock.now

        let examples = await service.examples(for: "Deploy Cloud Flower today")

        XCTAssertEqual(examples.first?.sampleID, seeded.id)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(50))
        await learningTask.value
    }

    func testExamplesReturnWhileLearningPersistenceIsBlocked() async {
        let persistenceStarted = expectation(description: "learning persistence started")
        let seeded = sample()
        let store = BlockingLearningBatchCorrectionStore(
            samples: [seeded],
            started: persistenceStarted
        )
        let service = CorrectionLearningService(
            store: store,
            extractor: FixedCorrectionExtractor(hunks: [CorrectionHunk(
                original: "Air Type",
                replacement: "Airtype",
                contextBefore: "Use",
                contextAfter: "today"
            )])
        )
        let learningTask = Task {
            await service.learn(
                original: "Use Air Type today",
                final: "Use Airtype today",
                applicationBundleID: "com.example.editor"
            )
        }
        await fulfillment(of: [persistenceStarted], timeout: 1)
        let clock = ContinuousClock()
        let start = clock.now

        let examples = await service.examples(for: "Deploy Cloud Flower today")

        XCTAssertEqual(examples.first?.sampleID, seeded.id)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(50))
        store.release()
        await learningTask.value
    }

    func testExamplesReturnBeforeMatchStatisticsPersistenceCompletes() async {
        let matchStarted = expectation(description: "match persistence started")
        let seeded = sample()
        let store = BlockingMatchCorrectionStore(samples: [seeded], started: matchStarted)
        let service = CorrectionLearningService(store: store)
        Task.detached {
            try? await Task.sleep(for: .milliseconds(200))
            store.release()
        }
        let clock = ContinuousClock()
        let start = clock.now

        let examples = await service.examples(for: "Deploy Cloud Flower today")

        XCTAssertEqual(examples.first?.sampleID, seeded.id)
        XCTAssertLessThan(start.duration(to: clock.now), .milliseconds(50))
        await fulfillment(of: [matchStarted], timeout: 1)
    }

    func testFailedMatchStatisticsWriteDoesNotDisableLaterRetrieval() async {
        let attempted = expectation(description: "first match write attempted")
        let seeded = sample()
        let store = FailOnceMatchCorrectionStore(samples: [seeded], attempted: attempted)
        let service = CorrectionLearningService(store: store)

        let first = await service.examples(for: "Deploy Cloud Flower today")
        await fulfillment(of: [attempted], timeout: 1)
        let second = await service.examples(for: "Deploy Cloud Flower today")

        XCTAssertEqual(first.first?.sampleID, seeded.id)
        XCTAssertEqual(second.first?.sampleID, seeded.id)
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
        let persistenceHealth = await service.persistenceHealth
        XCTAssertEqual(samplesAfterFailure, [storedSample])
        XCTAssertEqual(examplesAfterFailure.first?.sampleID, storedSample.id)
        XCTAssertEqual(persistenceHealth, .unavailable)
    }

    func testInitialLoadFailureReportsUnavailablePersistenceHealth() async {
        let service = CorrectionLearningService(store: FailingCorrectionStore())

        let persistenceHealth = await service.persistenceHealth

        XCTAssertEqual(persistenceHealth, .unavailable)
    }

    func testLearningWriteFailureReportsUnavailablePersistenceHealth() async {
        let service = CorrectionLearningService(store: WriteFailingCorrectionStore())

        await service.learn(
            original: "Use Cloud Flower.",
            final: "Use Cloudflare.",
            applicationBundleID: "com.example.editor"
        )
        let persistenceHealth = await service.persistenceHealth

        XCTAssertEqual(persistenceHealth, .unavailable)
    }

    func testTransientLearningFailureReconcilesAndLaterOperationRecovers() async {
        let store = FailOnceLearningBatchStore()
        let service = CorrectionLearningService(store: store)

        await service.learn(
            original: "Use Cloud Flower.",
            final: "Use Cloudflare.",
            applicationBundleID: "com.example.editor"
        )

        let samplesAfterFailure = await service.samples()
        let healthAfterFailure = await service.persistenceHealth
        XCTAssertTrue(samplesAfterFailure.isEmpty)
        XCTAssertEqual(healthAfterFailure, .unavailable)

        await service.learn(
            original: "Use Cloud Flower.",
            final: "Use Cloudflare.",
            applicationBundleID: "com.example.editor"
        )

        let samplesAfterRecovery = await service.samples()
        let healthAfterRecovery = await service.persistenceHealth
        XCTAssertEqual(samplesAfterRecovery.count, 1)
        XCTAssertEqual(try? store.loadSamples().count, 1)
        XCTAssertEqual(healthAfterRecovery, .available)
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

private final class BlockingCorrectionExtractor: CorrectionExtracting, @unchecked Sendable {
    private let started: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)

    init(started: XCTestExpectation) {
        self.started = started
    }

    func extract(original: String, final: String) -> [CorrectionHunk] {
        started.fulfill()
        gate.wait()
        return []
    }

    func release() {
        gate.signal()
    }
}

private struct FixedCorrectionExtractor: CorrectionExtracting {
    let hunks: [CorrectionHunk]

    func extract(original: String, final: String) -> [CorrectionHunk] {
        hunks
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

private final class BlockingMatchCorrectionStore: CorrectionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [CorrectionSample]
    private let started: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)

    init(samples: [CorrectionSample], started: XCTestExpectation) {
        self.samples = samples
        self.started = started
    }

    func loadSamples() throws -> [CorrectionSample] { lock.withLock { samples } }
    func upsert(sample: CorrectionSample) throws {}
    func deleteSamples(ids: [UUID]) throws {}
    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { [] }

    func markMatched(ids: [UUID], at date: Date) throws {
        started.fulfill()
        gate.wait()
        lock.withLock {
            for position in samples.indices where ids.contains(samples[position].id) {
                samples[position].matchCount += 1
                samples[position].lastMatchedAt = date
            }
        }
    }

    func release() {
        gate.signal()
    }
}

private final class BlockingLearningBatchCorrectionStore: CorrectionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [CorrectionSample]
    private var sessions: [EditSessionMetadata] = []
    private let started: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)

    init(samples: [CorrectionSample], started: XCTestExpectation) {
        self.samples = samples
        self.started = started
    }

    func loadSamples() throws -> [CorrectionSample] { lock.withLock { samples } }
    func upsert(sample: CorrectionSample) throws {}
    func deleteSamples(ids: [UUID]) throws {}
    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { lock.withLock { sessions } }
    func markMatched(ids: [UUID], at date: Date) throws {}

    func applyLearningBatch(
        upserting updatedSamples: [CorrectionSample],
        deleting removedIDs: [UUID],
        session: EditSessionMetadata
    ) throws {
        started.fulfill()
        gate.wait()
        lock.withLock {
            samples.removeAll { removedIDs.contains($0.id) }
            for sample in updatedSamples {
                samples.removeAll { $0.id == sample.id }
                samples.append(sample)
            }
            sessions.append(session)
        }
    }

    func release() {
        gate.signal()
    }
}

private final class FailOnceMatchCorrectionStore: CorrectionStoring, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var samples: [CorrectionSample]
    private var shouldFail = true
    private let attempted: XCTestExpectation

    init(samples: [CorrectionSample], attempted: XCTestExpectation) {
        self.samples = samples
        self.attempted = attempted
    }

    func loadSamples() throws -> [CorrectionSample] { lock.withLock { samples } }
    func upsert(sample: CorrectionSample) throws {}
    func deleteSamples(ids: [UUID]) throws {}
    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { [] }

    func markMatched(ids: [UUID], at date: Date) throws {
        let fails = lock.withLock { () -> Bool in
            defer { shouldFail = false }
            return shouldFail
        }
        attempted.fulfill()
        if fails { throw Failure() }
    }
}

private final class FailOnceLearningBatchStore: CorrectionStoring, @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var samples: [CorrectionSample] = []
    private var sessions: [EditSessionMetadata] = []
    private var shouldFail = true

    func loadSamples() throws -> [CorrectionSample] { lock.withLock { samples } }

    func upsert(sample: CorrectionSample) throws {
        let fails = lock.withLock { () -> Bool in
            defer { shouldFail = false }
            return shouldFail
        }
        if fails { throw Failure() }
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

    func loadSessions() throws -> [EditSessionMetadata] { lock.withLock { sessions } }
    func markMatched(ids: [UUID], at date: Date) throws {}

    func applyLearningBatch(
        upserting updatedSamples: [CorrectionSample],
        deleting removedIDs: [UUID],
        session: EditSessionMetadata
    ) throws {
        try lock.withLock {
            if shouldFail {
                shouldFail = false
                throw Failure()
            }
            samples.removeAll { removedIDs.contains($0.id) }
            for sample in updatedSamples {
                samples.removeAll { $0.id == sample.id }
                samples.append(sample)
            }
            sessions.append(session)
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

private struct WriteFailingCorrectionStore: CorrectionStoring {
    struct Failure: Error {}
    func loadSamples() throws -> [CorrectionSample] { [] }
    func upsert(sample: CorrectionSample) throws { throw Failure() }
    func deleteSamples(ids: [UUID]) throws {}
    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { [] }
    func markMatched(ids: [UUID], at date: Date) throws {}
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
