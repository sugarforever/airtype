import Foundation

public enum VocabularyRepositoryError: Error, Equatable {
    case emptyTerm
    case duplicateTerm
}

public actor VocabularyRepository {
    private let store: any VocabularyStoring
    private var terms: [VocabularyTerm]
    private var normalizedValues: Set<String>

    public init(store: any VocabularyStoring) throws {
        self.store = store
        let loadedTerms = try store.loadTerms().sorted(by: Self.isNewerFirst)
        self.terms = loadedTerms
        self.normalizedValues = Set(loadedTerms.map(\.normalizedValue))
    }

    public func allTerms() -> [VocabularyTerm] {
        terms
    }

    public func add(_ value: String, now: Date = Date()) throws -> VocabularyTerm {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = Self.normalize(trimmedValue)
        guard !normalizedValue.isEmpty else {
            throw VocabularyRepositoryError.emptyTerm
        }
        guard !normalizedValues.contains(normalizedValue) else {
            throw VocabularyRepositoryError.duplicateTerm
        }

        let term = VocabularyTerm(
            id: UUID(),
            value: trimmedValue,
            normalizedValue: normalizedValue,
            createdAt: now
        )
        try store.insert(term)
        normalizedValues.insert(normalizedValue)
        let insertionIndex = terms.firstIndex { Self.isNewerFirst(term, $0) } ?? terms.endIndex
        terms.insert(term, at: insertionIndex)
        return term
    }

    public func delete(id: UUID) throws {
        try store.delete(id: id)
        if let removedTerm = terms.first(where: { $0.id == id }) {
            normalizedValues.remove(removedTerm.normalizedValue)
        }
        terms.removeAll { $0.id == id }
    }

    public func promptTerms(tokenBudget: Int = 300) -> [String] {
        var remainingBudget = tokenBudget
        var promptTerms: [String] = []

        for term in terms {
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
