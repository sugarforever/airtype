import Foundation
import XCTest
@testable import CorrectionLearningCore
@testable import DashboardCore
@testable import VocabularyCore

@MainActor
@available(macOS 14.0, *)
final class VocabularyPageModelTests: XCTestCase {
    func testVocabularyDisplayIsLocalizedSortedButPromptOrderRemainsRepositoryOwned() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("Alpha", now: Date(timeIntervalSince1970: 1))
        _ = try await repository.add("Zulu", now: Date(timeIntervalSince1970: 2))
        let learningService = CorrectionLearningService(store: MemoryCorrectionStore())
        let model = VocabularyPageModel(repository: repository, learningService: learningService)

        await model.load()

        XCTAssertEqual(model.visibleTerms.map(\.value), ["Alpha", "Zulu"])
        XCTAssertEqual(
            model.visibleTerms.map(\.value),
            model.visibleTerms.map(\.value).sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        )
        let promptTerms = await repository.promptTerms()
        XCTAssertEqual(promptTerms, ["Zulu", "Alpha"])
    }

    func testDuplicateTermProducesInlineValidationWithoutLocalFailure() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("Cloudflare")
        let model = VocabularyPageModel(
            repository: repository,
            learningService: CorrectionLearningService(store: MemoryCorrectionStore())
        )
        await model.load()
        model.termText = "  cloudflare  "

        await model.addTerm()

        XCTAssertNotNil(model.validationText)
        XCTAssertNil(model.localErrorText)
        XCTAssertEqual(model.terms.map(\.value), ["Cloudflare"])
    }

    func testEmptyTermProducesInlineValidationWithoutRepositoryMutation() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        let model = VocabularyPageModel(
            repository: repository,
            learningService: CorrectionLearningService(store: MemoryCorrectionStore())
        )
        model.termText = "  \n "

        await model.addTerm()

        XCTAssertNotNil(model.validationText)
        let storedTerms = await repository.allTerms()
        XCTAssertTrue(storedTerms.isEmpty)
    }

    func testLearnedCorrectionFilteringMatchesRecognizedOrCorrectedText() async throws {
        let cloudflare = correction(original: "Cloud Flower", replacement: "Cloudflare")
        let swift = correction(original: "Swiff", replacement: "Swift")
        let model = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: CorrectionLearningService(
                store: MemoryCorrectionStore(samples: [cloudflare, swift])
            )
        )
        await model.load()

        model.query = "cloud"
        XCTAssertEqual(model.visibleCorrections.map(\.id), [cloudflare.id])

        model.query = "swift"
        XCTAssertEqual(model.visibleCorrections.map(\.id), [swift.id])
    }

    func testAddFailureKeepsSnapshotAndPublishesLocalError() async throws {
        let existing = VocabularyTerm(
            id: UUID(),
            value: "Existing",
            normalizedValue: "existing",
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let repository = try VocabularyRepository(
            store: InsertFailingVocabularyStore(terms: [existing])
        )
        let model = VocabularyPageModel(
            repository: repository,
            learningService: CorrectionLearningService(store: MemoryCorrectionStore())
        )
        await model.load()
        model.termText = "New term"

        await model.addTerm()

        XCTAssertEqual(model.terms, [existing])
        XCTAssertNotNil(model.localErrorText)
        XCTAssertFalse(model.isLoading)
    }

    func testDeletingTermRefreshesVisibleSnapshot() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        let term = try await repository.add("Delete me")
        let model = VocabularyPageModel(
            repository: repository,
            learningService: CorrectionLearningService(store: MemoryCorrectionStore())
        )
        await model.load()

        await model.deleteTerm(id: term.id)

        XCTAssertTrue(model.terms.isEmpty)
        XCTAssertNil(model.localErrorText)
    }

    func testDeletingCorrectionRefreshesVisibleSnapshot() async throws {
        let sample = correction(original: "Air Type", replacement: "Airtype")
        let model = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: CorrectionLearningService(
                store: MemoryCorrectionStore(samples: [sample])
            )
        )
        await model.load()

        await model.deleteCorrection(id: sample.id)

        XCTAssertTrue(model.corrections.isEmpty)
        XCTAssertNil(model.localErrorText)
    }

    func testMissingPersistenceDependenciesDegradeToEmptyErrorState() async {
        let model = VocabularyPageModel(repository: nil, learningService: nil)

        await model.load()

        XCTAssertTrue(model.terms.isEmpty)
        XCTAssertTrue(model.corrections.isEmpty)
        XCTAssertNotNil(model.localErrorText)
        XCTAssertFalse(model.isLoading)
    }

    func testCorrectionLoadFailurePublishesLocalError() async throws {
        let model = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: CorrectionLearningService(
                store: LoadFailingCorrectionStore()
            )
        )

        await model.load()

        XCTAssertTrue(model.corrections.isEmpty)
        XCTAssertNotNil(model.localErrorText)
        XCTAssertFalse(model.isLoading)
    }

    func testCorrectionWriteFailureMarksStaleSnapshotWithLocalError() async throws {
        let learningService = CorrectionLearningService(
            store: WriteFailingCorrectionStore()
        )
        await learningService.learn(
            original: "Use Cloud Flower.",
            final: "Use Cloudflare.",
            applicationBundleID: "com.example.editor"
        )
        let model = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: learningService
        )

        await model.load()

        XCTAssertTrue(model.corrections.isEmpty)
        XCTAssertNotNil(model.localErrorText)
        XCTAssertFalse(model.isLoading)
    }

    func testSuccessfulTermAddDoesNotClearPersistentCorrectionError() async throws {
        let model = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: CorrectionLearningService(store: LoadFailingCorrectionStore())
        )
        await model.load()
        model.termText = "Cloudflare"

        let succeeded = await model.addTerm()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.terms.map(\.value), ["Cloudflare"])
        XCTAssertEqual(model.localErrorText, "Learned-correction storage is unavailable.")
    }

    func testSuccessfulCorrectionDeleteDoesNotClearPersistentProperNounError() async throws {
        let sample = correction(original: "Air Type", replacement: "Airtype")
        let model = VocabularyPageModel(
            repository: nil,
            learningService: CorrectionLearningService(
                store: MemoryCorrectionStore(samples: [sample])
            )
        )
        await model.load()

        await model.deleteCorrection(id: sample.id)

        XCTAssertTrue(model.corrections.isEmpty)
        XCTAssertEqual(model.localErrorText, "Proper-noun storage is unavailable.")
    }

    func testLearningPublishesToSharedHomeAndVocabularyModels() async throws {
        let learningService = CorrectionLearningService(store: MemoryCorrectionStore())
        let homeModel = HomePageModel(learningService: learningService)
        let vocabularyModel = VocabularyPageModel(
            repository: try VocabularyRepository(store: MemoryVocabularyStore()),
            learningService: learningService
        )
        let homeObservation = Task { await homeModel.observeCorrectionUpdates() }
        let vocabularyObservation = Task { await vocabularyModel.observeCorrectionUpdates() }
        defer {
            homeObservation.cancel()
            vocabularyObservation.cancel()
        }
        await Task.yield()

        await learningService.learn(
            original: "Use Cloud Flower today.",
            final: "Use Cloudflare today.",
            applicationBundleID: "com.example.editor"
        )

        for _ in 0..<100 {
            if homeModel.todayLearnedCorrectionCount == 1,
               vocabularyModel.corrections.count == 1 {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(homeModel.todayLearnedCorrectionCount, 1)
        XCTAssertEqual(vocabularyModel.corrections.count, 1)
    }

    private func correction(original: String, replacement: String) -> CorrectionSample {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return CorrectionSample(
            id: UUID(),
            original: original,
            replacement: replacement,
            normalizedOriginal: original.lowercased(),
            contextBefore: "before",
            contextAfter: "after",
            correctionCount: 1,
            matchCount: 0,
            createdAt: date,
            lastCorrectedAt: date,
            lastMatchedAt: nil
        )
    }
}

private final class MemoryVocabularyStore: VocabularyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var terms: [VocabularyTerm]

    init(terms: [VocabularyTerm] = []) {
        self.terms = terms
    }

    func loadTerms() throws -> [VocabularyTerm] {
        lock.withLock { terms }
    }

    func insert(_ term: VocabularyTerm) throws {
        lock.withLock { terms.append(term) }
    }

    func delete(id: UUID) throws {
        lock.withLock { terms.removeAll { $0.id == id } }
    }
}

private final class InsertFailingVocabularyStore: VocabularyStoring, @unchecked Sendable {
    struct Failure: Error {}
    private let terms: [VocabularyTerm]

    init(terms: [VocabularyTerm]) {
        self.terms = terms
    }

    func loadTerms() throws -> [VocabularyTerm] { terms }
    func insert(_ term: VocabularyTerm) throws { throw Failure() }
    func delete(id: UUID) throws {}
}

private final class MemoryCorrectionStore: CorrectionStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [CorrectionSample]

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

    func recordSession(_ session: EditSessionMetadata) throws {}
    func loadSessions() throws -> [EditSessionMetadata] { [] }
    func markMatched(ids: [UUID], at date: Date) throws {}
}

private struct LoadFailingCorrectionStore: CorrectionStoring {
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
