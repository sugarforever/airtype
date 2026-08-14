import Foundation

public struct VocabularyTerm: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let value: String
    public let normalizedValue: String
    public let createdAt: Date

    public init(
        id: UUID,
        value: String,
        normalizedValue: String,
        createdAt: Date
    ) {
        self.id = id
        self.value = value
        self.normalizedValue = normalizedValue
        self.createdAt = createdAt
    }
}

public protocol VocabularyStoring: Sendable {
    func loadTerms() throws -> [VocabularyTerm]
    func insert(_ term: VocabularyTerm) throws
    func delete(id: UUID) throws
}
