import Foundation

/// Persists recent transcriptions locally so text is never lost.
class TranscriptionHistory {
    static let shared = TranscriptionHistory()

    private let key = "transcriptionHistory"
    private let maxEntries = 50

    struct Entry: Codable, Identifiable {
        let id: UUID
        let text: String
        let date: Date
        let inserted: Bool

        init(text: String, inserted: Bool) {
            self.id = UUID()
            self.text = text
            self.date = Date()
            self.inserted = inserted
        }
    }

    private init() {}

    var entries: [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    @discardableResult
    func save(text: String, inserted: Bool) -> Entry {
        var list = entries
        let entry = Entry(text: text, inserted: inserted)
        list.insert(entry, at: 0)
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return entry
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
