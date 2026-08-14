import XCTest
@testable import CorrectionLearningCore

final class CorrectionStoreTests: XCTestCase {
    private var databaseURL: URL!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("airtype-corrections-\(UUID().uuidString).sqlite3")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }

    func testRoundTripPersistsCorrectionSample() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        let expected = sample(id: UUID())

        try store.upsert(sample: expected)

        XCTAssertEqual(try store.loadSamples(), [expected])
    }

    func testUpsertReplacesMutableStatisticsWithoutDuplicatingSample() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        var updated = sample(id: UUID())
        try store.upsert(sample: updated)
        updated.correctionCount = 4
        updated.matchCount = 2
        updated.lastMatchedAt = Date(timeIntervalSince1970: 1_700_000_100)

        try store.upsert(sample: updated)

        XCTAssertEqual(try store.loadSamples(), [updated])
    }

    func testDeleteRemovesOnlyRequestedSamples() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        let kept = sample(id: UUID(), original: "kept")
        let removed = sample(id: UUID(), original: "removed")
        try store.upsert(sample: kept)
        try store.upsert(sample: removed)

        try store.deleteSamples(ids: [removed.id])

        XCTAssertEqual(try store.loadSamples(), [kept])
    }

    func testEditSessionsRetainOnlyLatestOneThousandMetadataRows() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for position in 0..<1_005 {
            try store.recordSession(EditSessionMetadata(
                id: UUID(),
                applicationBundleID: "com.example.editor",
                originalCharacterCount: position,
                status: .learned,
                createdAt: start.addingTimeInterval(Double(position)),
                completedAt: start.addingTimeInterval(Double(position + 1))
            ))
        }

        let sessions = try store.loadSessions()

        XCTAssertEqual(sessions.count, 1_000)
        XCTAssertEqual(sessions.first?.originalCharacterCount, 5)
        XCTAssertEqual(sessions.last?.originalCharacterCount, 1_004)
    }

    func testMarkMatchedUpdatesOnlySelectedSamples() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        let selected = sample(id: UUID(), original: "selected")
        let untouched = sample(id: UUID(), original: "untouched")
        try store.upsert(sample: selected)
        try store.upsert(sample: untouched)
        let matchedAt = Date(timeIntervalSince1970: 1_700_000_500)

        try store.markMatched(ids: [selected.id], at: matchedAt)
        let loaded = try store.loadSamples()

        XCTAssertEqual(loaded.first(where: { $0.id == selected.id })?.matchCount, 1)
        XCTAssertEqual(loaded.first(where: { $0.id == selected.id })?.lastMatchedAt, matchedAt)
        XCTAssertEqual(loaded.first(where: { $0.id == untouched.id })?.matchCount, 0)
    }

    private func sample(id: UUID, original: String = "Cloud Flower") -> CorrectionSample {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return CorrectionSample(
            id: id,
            original: original,
            replacement: "Cloudflare",
            normalizedOriginal: CorrectionSampleIndex.normalize(original),
            contextBefore: "Deploy",
            contextAfter: "Workers",
            correctionCount: 1,
            matchCount: 0,
            createdAt: date,
            lastCorrectedAt: date,
            lastMatchedAt: nil
        )
    }
}
