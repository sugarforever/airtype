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
