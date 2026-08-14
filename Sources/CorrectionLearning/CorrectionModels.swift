import Foundation

public struct CorrectionHunk: Equatable, Sendable {
    public let original: String
    public let replacement: String
    public let contextBefore: String
    public let contextAfter: String

    public init(
        original: String,
        replacement: String,
        contextBefore: String,
        contextAfter: String
    ) {
        self.original = original
        self.replacement = replacement
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

public protocol CorrectionExtracting: Sendable {
    func extract(original: String, final: String) -> [CorrectionHunk]
}

public struct CorrectionSample: Equatable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let original: String
    public let replacement: String
    public let normalizedOriginal: String
    public let contextBefore: String
    public let contextAfter: String
    public var correctionCount: Int
    public var matchCount: Int
    public let createdAt: Date
    public var lastCorrectedAt: Date
    public var lastMatchedAt: Date?

    public init(
        id: UUID,
        original: String,
        replacement: String,
        normalizedOriginal: String,
        contextBefore: String,
        contextAfter: String,
        correctionCount: Int,
        matchCount: Int,
        createdAt: Date,
        lastCorrectedAt: Date,
        lastMatchedAt: Date?
    ) {
        self.id = id
        self.original = original
        self.replacement = replacement
        self.normalizedOriginal = normalizedOriginal
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.correctionCount = correctionCount
        self.matchCount = matchCount
        self.createdAt = createdAt
        self.lastCorrectedAt = lastCorrectedAt
        self.lastMatchedAt = lastMatchedAt
    }
}

public struct CorrectionPromptExample: Equatable, Sendable {
    public let sampleID: UUID
    public let original: String
    public let replacement: String
    public let contextBefore: String
    public let contextAfter: String

    public var estimatedTokenCount: Int {
        let byteCount = original.utf8.count
            + replacement.utf8.count
            + contextBefore.utf8.count
            + contextAfter.utf8.count
        return max(1, (byteCount + 3) / 4)
    }
}

public struct EditSessionMetadata: Equatable, Sendable {
    public enum Status: String, Sendable {
        case learned
        case discarded
        case unsupported
    }

    public let id: UUID
    public let applicationBundleID: String
    public let originalCharacterCount: Int
    public let status: Status
    public let createdAt: Date
    public let completedAt: Date

    public init(
        id: UUID,
        applicationBundleID: String,
        originalCharacterCount: Int,
        status: Status,
        createdAt: Date,
        completedAt: Date
    ) {
        self.id = id
        self.applicationBundleID = applicationBundleID
        self.originalCharacterCount = originalCharacterCount
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
