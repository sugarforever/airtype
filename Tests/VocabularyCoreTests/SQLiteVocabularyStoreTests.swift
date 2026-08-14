import Foundation
import XCTest
@testable import VocabularyCore

final class SQLiteVocabularyStoreTests: XCTestCase {
    func testRoundTripReturnsNewestFirst() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteVocabularyStore(url: databaseURL)

        try store.insert(VocabularyTerm(
            id: UUID(),
            value: "Old",
            normalizedValue: "old",
            createdAt: Date(timeIntervalSince1970: 1)
        ))
        try store.insert(VocabularyTerm(
            id: UUID(),
            value: "New",
            normalizedValue: "new",
            createdAt: Date(timeIntervalSince1970: 2)
        ))

        XCTAssertEqual(try store.loadTerms().map(\.value), ["New", "Old"])
    }

    func testNormalizedValueIsUnique() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteVocabularyStore(url: databaseURL)

        try store.insert(VocabularyTerm(
            id: UUID(),
            value: "Cloudflare",
            normalizedValue: "cloudflare",
            createdAt: .now
        ))

        XCTAssertThrowsError(try store.insert(VocabularyTerm(
            id: UUID(),
            value: "CLOUDFLARE",
            normalizedValue: "cloudflare",
            createdAt: .now
        )))
    }

    func testDeleteRemovesTermPersistently() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try SQLiteVocabularyStore(url: databaseURL)
        let term = VocabularyTerm(
            id: UUID(),
            value: "Cloudflare",
            normalizedValue: "cloudflare",
            createdAt: .now
        )
        try store.insert(term)

        try store.delete(id: term.id)

        XCTAssertEqual(try store.loadTerms(), [])
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite3")
    }

    private func removeDatabase(at url: URL) {
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        try? manager.removeItem(atPath: url.path + "-shm")
        try? manager.removeItem(atPath: url.path + "-wal")
    }
}
