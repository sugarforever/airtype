import Foundation
import XCTest
@testable import VocabularyCore

final class VocabularyRepositoryTests: XCTestCase {
    func testInitializationSurfacesStoreLoadFailure() {
        XCTAssertThrowsError(try VocabularyRepository(store: FailingVocabularyStore()))
    }

    func testAddTrimsAndRejectsNormalizedDuplicate() async throws {
        let store = MemoryVocabularyStore()
        let repository = try VocabularyRepository(store: store)
        let first = try await repository.add("  Cloudflare  ", now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(first.value, "Cloudflare")
        do {
            _ = try await repository.add("cloudflare", now: .now)
            XCTFail("Expected duplicateTerm")
        } catch VocabularyRepositoryError.duplicateTerm {
            // Expected.
        }
    }

    func testAddNormalizesCanonicalCompositionAndWhitespace() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())

        let term = try await repository.add("  Cafe\u{301}\t\nPlatform  ", now: .now)

        XCTAssertEqual(term.normalizedValue, "café platform")
    }

    func testDeleteRemovesAddedTermFromAllTerms() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        let term = try await repository.add("Cloudflare", now: .now)

        try await repository.delete(id: term.id)

        let terms = await repository.allTerms()
        XCTAssertEqual(terms, [])
    }

    func testPromptTermsAreNewestFirstAndNeverExceedBudget() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("OldTerm", now: Date(timeIntervalSince1970: 1))
        _ = try await repository.add("NewestTerm", now: Date(timeIntervalSince1970: 2))

        let terms = await repository.promptTerms(tokenBudget: 3)
        XCTAssertEqual(terms, ["NewestTerm"])
    }

    func testPromptTermsUsesDefaultThreeHundredTokenBudget() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add(String(repeating: "a", count: 1_201), now: .now)

        let terms = await repository.promptTerms()

        XCTAssertEqual(terms, [])
    }

    func testPromptTermsStopsBeforeFirstTermThatExceedsRemainingBudget() async throws {
        let repository = try VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("new", now: Date(timeIntervalSince1970: 2))
        _ = try await repository.add("longest", now: Date(timeIntervalSince1970: 1))
        _ = try await repository.add("old", now: Date(timeIntervalSince1970: 0))

        let terms = await repository.promptTerms(tokenBudget: 2)
        XCTAssertEqual(terms, ["new"])
    }
}

private final class MemoryVocabularyStore: VocabularyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var terms: [VocabularyTerm] = []

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

private struct FailingVocabularyStore: VocabularyStoring {
    struct Failure: Error {}

    func loadTerms() throws -> [VocabularyTerm] { throw Failure() }
    func insert(_ term: VocabularyTerm) throws { throw Failure() }
    func delete(id: UUID) throws { throw Failure() }
}
