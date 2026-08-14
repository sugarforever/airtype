import Foundation

public extension Notification.Name {
    static let transcriptionHistoryDidChange = Notification.Name(
        "TranscriptionHistoryDidChange"
    )
}

/// Persists recent transcriptions locally so text is never lost.
public final class TranscriptionHistory {
    public static let shared = TranscriptionHistory()

    private static let maxEntries = 50

    private let userDefaults: UserDefaults
    private let key: String
    let notificationCenter: NotificationCenter

    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let text: String
        public let date: Date
        public let inserted: Bool

        public init(
            id: UUID = UUID(),
            text: String,
            date: Date = Date(),
            inserted: Bool
        ) {
            self.id = id
            self.text = text
            self.date = date
            self.inserted = inserted
        }
    }

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "transcriptionHistory",
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.notificationCenter = notificationCenter
    }

    public var entries: [Entry] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    @discardableResult
    public func save(text: String, inserted: Bool) -> Entry {
        var list = entries
        let entry = Entry(text: text, inserted: inserted)
        list.insert(entry, at: 0)
        if list.count > Self.maxEntries {
            list = Array(list.prefix(Self.maxEntries))
        }
        if let data = try? JSONEncoder().encode(list) {
            userDefaults.set(data, forKey: key)
        }
        notificationCenter.post(name: .transcriptionHistoryDidChange, object: self)
        return entry
    }

    public func clear() {
        userDefaults.removeObject(forKey: key)
        notificationCenter.post(name: .transcriptionHistoryDidChange, object: self)
    }
}
