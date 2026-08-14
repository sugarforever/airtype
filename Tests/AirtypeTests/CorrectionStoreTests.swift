import XCTest
import SQLite3
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

    func testOlderDeferredMatchDoesNotRegressPersistedLastMatchedAt() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        var matched = sample(id: UUID())
        let newestMatch = Date(timeIntervalSince1970: 1_700_000_500)
        matched.matchCount = 1
        matched.lastMatchedAt = newestMatch
        try store.upsert(sample: matched)

        try store.markMatched(
            ids: [matched.id],
            at: Date(timeIntervalSince1970: 1_700_000_400)
        )

        let loaded = try XCTUnwrap(try store.loadSamples().first)
        XCTAssertEqual(loaded.matchCount, 2)
        XCTAssertEqual(loaded.lastMatchedAt, newestMatch)
    }

    func testLearningBatchRollsBackEveryRowWhenSecondUpsertFails() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        defer { sqlite3_close(connection) }
        XCTAssertEqual(sqlite3_exec(connection, """
            CREATE TRIGGER fail_second_learning_upsert
            BEFORE INSERT ON correction_samples
            WHEN NEW.original = 'trigger failure'
            BEGIN
                SELECT RAISE(ABORT, 'injected failure');
            END;
            """, nil, nil, nil), SQLITE_OK)
        let first = sample(id: UUID(), original: "first")
        let second = sample(id: UUID(), original: "trigger failure")
        let session = editSession()

        XCTAssertThrowsError(try store.applyLearningBatch(
            upserting: [first, second],
            deleting: [],
            session: session
        ))

        XCTAssertTrue(try store.loadSamples().isEmpty)
        XCTAssertTrue(try store.loadSessions().isEmpty)
    }

    func testBusyLearningBatchCanSucceedOnTheSameStoreAfterLockClears() throws {
        let store = try SQLiteCorrectionStore(url: databaseURL)
        var lockConnection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &lockConnection), SQLITE_OK)
        defer { sqlite3_close(lockConnection) }
        XCTAssertEqual(sqlite3_exec(lockConnection, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        let expected = sample(id: UUID())
        let session = editSession()

        XCTAssertThrowsError(try store.applyLearningBatch(
            upserting: [expected],
            deleting: [],
            session: session
        )) { error in
            guard case CorrectionStoreError.busy = error else {
                return XCTFail("Expected typed busy error, got \(error)")
            }
        }
        XCTAssertEqual(sqlite3_exec(lockConnection, "ROLLBACK", nil, nil, nil), SQLITE_OK)

        try store.applyLearningBatch(
            upserting: [expected],
            deleting: [],
            session: session
        )

        let reopened = try SQLiteCorrectionStore(url: databaseURL)
        XCTAssertEqual(try reopened.loadSamples(), [expected])
        XCTAssertEqual(try reopened.loadSessions(), [session])
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

    private func editSession() -> EditSessionMetadata {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        return EditSessionMetadata(
            id: UUID(),
            applicationBundleID: "com.example.editor",
            originalCharacterCount: 12,
            status: .learned,
            createdAt: date,
            completedAt: date
        )
    }
}
