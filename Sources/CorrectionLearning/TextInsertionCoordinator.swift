import Foundation

public enum TextInsertionOutcome: Equatable, Sendable {
    case accessibility(AccessibilityInsertion)
    case accessibilityWithoutObservation
    case paste
}

public enum CorrectionLearningFlow {
    public static func insertionToTrack(
        learningEnabled: Bool,
        outcome: TextInsertionOutcome
    ) -> AccessibilityInsertion? {
        guard learningEnabled, case .accessibility(let insertion) = outcome else {
            return nil
        }
        return insertion
    }
}

@MainActor
public final class TextInsertionCoordinator {
    public typealias PasteHandler = @MainActor (String) async throws -> Void

    private let client: any AccessibilityTextClientProtocol
    private let paste: PasteHandler

    public init(
        client: any AccessibilityTextClientProtocol,
        paste: @escaping PasteHandler
    ) {
        self.client = client
        self.paste = paste
    }

    public func insert(text: String) async throws -> TextInsertionOutcome {
        switch client.insert(text: text) {
        case .observable(let insertion):
            return .accessibility(insertion)
        case .insertedWithoutObservation:
            return .accessibilityWithoutObservation
        case .unsupported:
            try await paste(text)
            return .paste
        case .permissionDenied:
            throw AccessibilityTextError.permissionDenied
        }
    }
}
