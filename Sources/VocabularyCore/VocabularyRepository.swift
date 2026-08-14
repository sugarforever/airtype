import Foundation

public enum VocabularyRepositoryError: Error, Equatable {
    case duplicateTerm
}

public actor VocabularyRepository {
    private let store: any VocabularyStoring
    private var terms: [VocabularyTerm]

    public init(store: any VocabularyStoring) throws {
        self.store = store
        self.terms = try store.loadTerms()
    }

    public func allTerms() -> [VocabularyTerm] {
        terms
    }

    public func add(_ value: String, now: Date = Date()) throws -> VocabularyTerm {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = Self.normalize(trimmedValue)
        guard !terms.contains(where: { $0.normalizedValue == normalizedValue }) else {
            throw VocabularyRepositoryError.duplicateTerm
        }

        let term = VocabularyTerm(
            id: UUID(),
            value: trimmedValue,
            normalizedValue: normalizedValue,
            createdAt: now
        )
        try store.insert(term)
        terms.append(term)
        return term
    }

    public func delete(id: UUID) throws {
        try store.delete(id: id)
        terms.removeAll { $0.id == id }
    }

    public func promptTerms(tokenBudget: Int = 300) -> [String] {
        var remainingBudget = tokenBudget
        var promptTerms: [String] = []

        for term in terms.sorted(by: Self.isNewerFirst) {
            let tokenCount = max(1, (term.value.utf8.count + 3) / 4)
            guard tokenCount <= remainingBudget else { break }
            promptTerms.append(term.value)
            remainingBudget -= tokenCount
        }

        return promptTerms
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isNewerFirst(_ lhs: VocabularyTerm, _ rhs: VocabularyTerm) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
