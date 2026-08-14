import Foundation
import SQLite3

public protocol CorrectionStoring: Sendable {
    func loadSamples() throws -> [CorrectionSample]
    func upsert(sample: CorrectionSample) throws
    func deleteSamples(ids: [UUID]) throws
    func recordSession(_ session: EditSessionMetadata) throws
    func loadSessions() throws -> [EditSessionMetadata]
    func markMatched(ids: [UUID], at date: Date) throws
    func applyLearningBatch(
        upserting samples: [CorrectionSample],
        deleting ids: [UUID],
        session: EditSessionMetadata
    ) throws
}

public extension CorrectionStoring {
    func applyLearningBatch(
        upserting samples: [CorrectionSample],
        deleting ids: [UUID],
        session: EditSessionMetadata
    ) throws {
        for sample in samples {
            try upsert(sample: sample)
        }
        try deleteSamples(ids: ids)
        try recordSession(session)
    }
}

public enum CorrectionStoreError: Error, Sendable {
    case openFailed(String)
    case busy
    case locked
    case operationFailed(String)
    case invalidStoredValue

    var isTransientLockContention: Bool {
        switch self {
        case .busy, .locked:
            true
        case .openFailed, .operationFailed, .invalidStoredValue:
            false
        }
    }
}

public final class SQLiteCorrectionStore: CorrectionStoring, @unchecked Sendable {
    private let database: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        var connection: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let connection { sqlite3_close(connection) }
            throw CorrectionStoreError.openFailed(message)
        }
        database = connection
        sqlite3_busy_timeout(database, 100)

        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute(Self.samplesSchema)
            try execute(Self.sessionsSchema)
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func loadSamples() throws -> [CorrectionSample] {
        let statement = try prepare("""
            SELECT id, original, replacement, normalized_original,
                   context_before, context_after, correction_count, match_count,
                   created_at, last_corrected_at, last_matched_at
            FROM correction_samples
            ORDER BY created_at ASC, id ASC
            """)
        defer { sqlite3_finalize(statement) }
        var result: [CorrectionSample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(statement, 0)),
                let original = optionalText(statement, 1),
                let replacement = optionalText(statement, 2),
                let normalized = optionalText(statement, 3),
                let before = optionalText(statement, 4),
                let after = optionalText(statement, 5)
            else { throw CorrectionStoreError.invalidStoredValue }
            result.append(CorrectionSample(
                id: id,
                original: original,
                replacement: replacement,
                normalizedOriginal: normalized,
                contextBefore: before,
                contextAfter: after,
                correctionCount: Int(sqlite3_column_int64(statement, 6)),
                matchCount: Int(sqlite3_column_int64(statement, 7)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)),
                lastCorrectedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                lastMatchedAt: sqlite3_column_type(statement, 10) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
            ))
        }
        try checkCompletion(statement)
        return result
    }

    public func upsert(sample: CorrectionSample) throws {
        try upsertWithoutTransaction(sample: sample)
    }

    private func upsertWithoutTransaction(sample: CorrectionSample) throws {
        let statement = try prepare("""
            INSERT INTO correction_samples (
                id, original, replacement, normalized_original,
                context_before, context_after, correction_count, match_count,
                created_at, last_corrected_at, last_matched_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                original = excluded.original,
                replacement = excluded.replacement,
                normalized_original = excluded.normalized_original,
                context_before = excluded.context_before,
                context_after = excluded.context_after,
                correction_count = excluded.correction_count,
                match_count = excluded.match_count,
                last_corrected_at = excluded.last_corrected_at,
                last_matched_at = excluded.last_matched_at
            """)
        defer { sqlite3_finalize(statement) }
        bind(sample.id.uuidString, to: 1, in: statement)
        bind(sample.original, to: 2, in: statement)
        bind(sample.replacement, to: 3, in: statement)
        bind(sample.normalizedOriginal, to: 4, in: statement)
        bind(sample.contextBefore, to: 5, in: statement)
        bind(sample.contextAfter, to: 6, in: statement)
        sqlite3_bind_int64(statement, 7, Int64(sample.correctionCount))
        sqlite3_bind_int64(statement, 8, Int64(sample.matchCount))
        sqlite3_bind_double(statement, 9, sample.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 10, sample.lastCorrectedAt.timeIntervalSince1970)
        if let lastMatchedAt = sample.lastMatchedAt {
            sqlite3_bind_double(statement, 11, lastMatchedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 11)
        }
        try stepDone(statement)
    }

    public func deleteSamples(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        try transaction {
            try deleteSamplesWithoutTransaction(ids: ids)
        }
    }

    private func deleteSamplesWithoutTransaction(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        let statement = try prepare("DELETE FROM correction_samples WHERE id = ?")
        defer { sqlite3_finalize(statement) }
        for id in ids {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(id.uuidString, to: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func recordSession(_ session: EditSessionMetadata) throws {
        try transaction {
            try recordSessionWithoutTransaction(session)
        }
    }

    private func recordSessionWithoutTransaction(_ session: EditSessionMetadata) throws {
        let statement = try prepare("""
            INSERT OR REPLACE INTO edit_sessions (
                id, application_bundle_id, original_character_count,
                status, created_at, completed_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        bind(session.id.uuidString, to: 1, in: statement)
        bind(session.applicationBundleID, to: 2, in: statement)
        sqlite3_bind_int64(statement, 3, Int64(session.originalCharacterCount))
        bind(session.status.rawValue, to: 4, in: statement)
        sqlite3_bind_double(statement, 5, session.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, session.completedAt.timeIntervalSince1970)
        try stepDone(statement)
        try execute("""
            DELETE FROM edit_sessions
            WHERE id IN (
                SELECT id FROM edit_sessions
                ORDER BY created_at DESC, id DESC
                LIMIT -1 OFFSET 1000
            )
            """)
    }

    public func loadSessions() throws -> [EditSessionMetadata] {
        let statement = try prepare("""
            SELECT id, application_bundle_id, original_character_count,
                   status, created_at, completed_at
            FROM edit_sessions
            ORDER BY created_at ASC, id ASC
            """)
        defer { sqlite3_finalize(statement) }
        var result: [EditSessionMetadata] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(statement, 0)),
                let bundleID = optionalText(statement, 1),
                let statusText = optionalText(statement, 3),
                let status = EditSessionMetadata.Status(rawValue: statusText)
            else { throw CorrectionStoreError.invalidStoredValue }
            result.append(EditSessionMetadata(
                id: id,
                applicationBundleID: bundleID,
                originalCharacterCount: Int(sqlite3_column_int64(statement, 2)),
                status: status,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                completedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            ))
        }
        try checkCompletion(statement)
        return result
    }

    public func markMatched(ids: [UUID], at date: Date) throws {
        guard !ids.isEmpty else { return }
        let statement = try prepare("""
            UPDATE correction_samples
            SET match_count = match_count + 1,
                last_matched_at = CASE
                    WHEN last_matched_at IS NULL OR last_matched_at < ? THEN ?
                    ELSE last_matched_at
                END
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        try transaction {
            for id in ids {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
                sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
                bind(id.uuidString, to: 3, in: statement)
                try stepDone(statement)
            }
        }
    }

    public func applyLearningBatch(
        upserting samples: [CorrectionSample],
        deleting ids: [UUID],
        session: EditSessionMetadata
    ) throws {
        try transaction {
            for sample in samples {
                try upsertWithoutTransaction(sample: sample)
            }
            try deleteSamplesWithoutTransaction(ids: ids)
            try recordSessionWithoutTransaction(session)
        }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try operation()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw storeError(code: result) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw storeError(code: result) }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        String(cString: sqlite3_column_text(statement, index))
    }

    private func optionalText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw storeError(code: result) }
    }

    private func checkCompletion(_ statement: OpaquePointer) throws {
        let result = sqlite3_errcode(database)
        guard result == SQLITE_OK || result == SQLITE_DONE else {
            throw storeError(code: result)
        }
    }

    private func storeError(code: Int32) -> CorrectionStoreError {
        switch code & 0xFF {
        case SQLITE_BUSY:
            return .busy
        case SQLITE_LOCKED:
            return .locked
        default:
            return .operationFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static let samplesSchema = """
        CREATE TABLE IF NOT EXISTS correction_samples (
            id TEXT PRIMARY KEY NOT NULL,
            original TEXT NOT NULL,
            replacement TEXT NOT NULL,
            normalized_original TEXT NOT NULL,
            context_before TEXT NOT NULL,
            context_after TEXT NOT NULL,
            correction_count INTEGER NOT NULL,
            match_count INTEGER NOT NULL,
            created_at REAL NOT NULL,
            last_corrected_at REAL NOT NULL,
            last_matched_at REAL
        )
        """

    private static let sessionsSchema = """
        CREATE TABLE IF NOT EXISTS edit_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            application_bundle_id TEXT NOT NULL,
            original_character_count INTEGER NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            completed_at REAL NOT NULL
        )
        """
}
