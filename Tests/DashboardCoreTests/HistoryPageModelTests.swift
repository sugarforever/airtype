import Foundation
import XCTest
@testable import DashboardCore

@MainActor
@available(macOS 14.0, *)
final class HistoryPageModelTests: XCTestCase {
    func testHistorySearchUsesLocalizedMatchingAndNeverTruncatesText() {
        let longText = String(repeating: "完整历史文字", count: 100)
        let model = HistoryPageModel(entries: [.fixture(text: longText)])

        model.query = "历史"

        XCTAssertEqual(model.filteredEntries.first?.text, longText)
    }

    func testClearHistoryRequiresConfirmationBeforeRemovingEntries() throws {
        let (history, defaults, key) = makeHistory()
        history.save(text: "Keep until confirmed", inserted: true)
        let model = HistoryPageModel(history: history)

        model.requestClear()

        XCTAssertTrue(model.isClearConfirmationPresented)
        XCTAssertEqual(model.entries.count, 1)

        model.confirmClear()

        XCTAssertFalse(model.isClearConfirmationPresented)
        XCTAssertTrue(model.entries.isEmpty)
        XCTAssertNil(defaults.data(forKey: key))
    }

    func testSuccessfulCopyPublishesAndClearsCopiedEntryFeedback() throws {
        let entry = TranscriptionHistory.Entry.fixture(text: "Copy all of this")
        var copiedText: String?
        let model = HistoryPageModel(entries: [entry]) { text in
            copiedText = text
            return true
        }

        model.copy(entry)

        XCTAssertEqual(copiedText, entry.text)
        XCTAssertEqual(model.copiedID, entry.id)

        model.clearCopyFeedback(for: entry.id)

        XCTAssertNil(model.copiedID)
    }

    func testFailedCopyLeavesFeedbackUnchanged() {
        let entry = TranscriptionHistory.Entry.fixture(text: "Unavailable clipboard")
        let model = HistoryPageModel(entries: [entry]) { _ in false }

        model.copy(entry)

        XCTAssertNil(model.copiedID)
    }

    func testHistoryRetainsFiftyNewestEntries() {
        let notificationCenter = NotificationCenter()
        let (history, _, _) = makeHistory(notificationCenter: notificationCenter)

        for index in 0..<51 {
            history.save(text: "Entry \(index)", inserted: true)
        }

        XCTAssertEqual(history.entries.count, 50)
        XCTAssertEqual(history.entries.first?.text, "Entry 50")
        XCTAssertEqual(history.entries.last?.text, "Entry 1")
    }

    func testHistoryPostsChangeNotificationsAfterSaveAndClear() {
        let notificationCenter = NotificationCenter()
        let (history, _, _) = makeHistory(notificationCenter: notificationCenter)
        var changeCount = 0
        let token = notificationCenter.addObserver(
            forName: .transcriptionHistoryDidChange,
            object: history,
            queue: nil
        ) { _ in
            changeCount += 1
        }
        defer { notificationCenter.removeObserver(token) }

        history.save(text: "Saved", inserted: true)
        history.clear()

        XCTAssertEqual(changeCount, 2)
    }

    func testHistoryDecodesExistingCodableRepresentation() throws {
        struct LegacyEntry: Codable {
            let id: UUID
            let text: String
            let date: Date
            let inserted: Bool
        }

        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = LegacyEntry(id: id, text: "Still readable", date: date, inserted: false)
        let (history, defaults, key) = makeHistory()
        defaults.set(try JSONEncoder().encode([legacy]), forKey: key)

        let decoded = try XCTUnwrap(history.entries.first)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.text, legacy.text)
        XCTAssertEqual(decoded.date, date)
        XCTAssertEqual(decoded.inserted, false)
    }

    private func makeHistory(
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> (TranscriptionHistory, UserDefaults, String) {
        let suite = "HistoryPageModelTests.\(UUID().uuidString)"
        let key = "testHistory"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            TranscriptionHistory(
                userDefaults: defaults,
                key: key,
                notificationCenter: notificationCenter
            ),
            defaults,
            key
        )
    }
}

private extension TranscriptionHistory.Entry {
    static func fixture(
        text: String,
        id: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        inserted: Bool = true
    ) -> Self {
        .init(id: id, text: text, date: date, inserted: inserted)
    }
}
