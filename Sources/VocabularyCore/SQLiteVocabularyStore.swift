import Foundation
import SQLite3

public enum VocabularyStoreError: Error {
    case openFailed(String)
    case operationFailed(String)
    case invalidStoredValue
}

public final class SQLiteVocabularyStore: VocabularyStoring, @unchecked Sendable {
    private let database: OpaquePointer
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        var connection: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &connection,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let connection { sqlite3_close(connection) }
            throw VocabularyStoreError.openFailed(message)
        }
        database = connection
        sqlite3_busy_timeout(database, 100)

        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=NORMAL")
            try execute(Self.schema)
        } catch {
            sqlite3_close(database)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func loadTerms() throws -> [VocabularyTerm] {
        let statement = try prepare("""
            SELECT id, value, normalized_value, created_at
            FROM vocabulary_terms
            ORDER BY created_at DESC, id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var terms: [VocabularyTerm] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(statement, 0)),
                let value = optionalText(statement, 1),
                let normalizedValue = optionalText(statement, 2)
            else {
                throw VocabularyStoreError.invalidStoredValue
            }
            terms.append(VocabularyTerm(
                id: id,
                value: value,
                normalizedValue: normalizedValue,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            ))
        }
        try checkCompletion()
        return terms
    }

    public func insert(_ term: VocabularyTerm) throws {
        let statement = try prepare("""
            INSERT INTO vocabulary_terms (id, value, normalized_value, created_at)
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        bind(term.id.uuidString, to: 1, in: statement)
        bind(term.value, to: 2, in: statement)
        bind(term.normalizedValue, to: 3, in: statement)
        sqlite3_bind_double(statement, 4, term.createdAt.timeIntervalSince1970)
        try stepDone(statement)
    }

    public func delete(id: UUID) throws {
        let statement = try prepare("DELETE FROM vocabulary_terms WHERE id = ?")
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, to: 1, in: statement)
        try stepDone(statement)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw VocabularyStoreError.operationFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw VocabularyStoreError.operationFailed(String(cString: sqlite3_errmsg(database)))
        }
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
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VocabularyStoreError.operationFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func checkCompletion() throws {
        guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
            throw VocabularyStoreError.operationFailed(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static let schema = """
        CREATE TABLE IF NOT EXISTS vocabulary_terms (
            id TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL,
            normalized_value TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL
        )
        """
}
