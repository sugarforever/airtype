import Foundation
import XCTest
@testable import DashboardCore
@testable import VocabularyCore

@MainActor
@available(macOS 14.0, *)
final class VocabularyPageModelTests: XCTestCase {
    func testAddingAndFilteringProperNounsNeedsOnlyVocabularyRepository() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        let model = VocabularyPageModel(repository: repository)
        await model.load()
        XCTAssertNil(model.localErrorText)
        model.termText = "  Cloudflare  "

        let succeeded = await model.addTerm()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.termText, "")
        XCTAssertEqual(model.terms.map(\.value), ["Cloudflare"])
        XCTAssertFalse(model.isLoading)

        model.query = "CLOUD"
        XCTAssertEqual(model.visibleTerms.map(\.value), ["Cloudflare"])
        model.query = "missing"
        XCTAssertTrue(model.visibleTerms.isEmpty)
        model.query = ""
        XCTAssertEqual(model.visibleTerms, model.terms)
    }

    func testVocabularyDisplayIsLocalizedSortedButPromptOrderRemainsRepositoryOwned() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("Alpha", now: Date(timeIntervalSince1970: 1))
        _ = try await repository.add("Zulu", now: Date(timeIntervalSince1970: 2))
        let model = VocabularyPageModel(repository: repository)

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
            repository: repository
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
            repository: repository
        )
        model.termText = "  \n "

        await model.addTerm()

        XCTAssertNotNil(model.validationText)
        let storedTerms = await repository.allTerms()
        XCTAssertTrue(storedTerms.isEmpty)
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
            repository: repository
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
            repository: repository
        )
        await model.load()

        await model.deleteTerm(id: term.id)

        XCTAssertTrue(model.terms.isEmpty)
        XCTAssertNil(model.localErrorText)
    }

    func testMissingRepositoryDegradesToEmptyErrorState() async {
        let model = VocabularyPageModel(repository: nil)

        await model.load()

        XCTAssertTrue(model.terms.isEmpty)
        XCTAssertNotNil(model.localErrorText)
        XCTAssertFalse(model.isLoading)
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
