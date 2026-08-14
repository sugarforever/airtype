import Foundation

@MainActor
public final class TextEditTracker {
    public typealias LearningHandler = @Sendable (
        _ original: String,
        _ final: String,
        _ applicationBundleID: String
    ) async -> Void

    private struct ActiveSession {
        let insertion: AccessibilityInsertion
        var didChange: Bool
    }

    private let client: any AccessibilityTextClientProtocol
    private let learningHandler: LearningHandler
    private var activeSession: ActiveSession?

    public var hasActiveSession: Bool { activeSession != nil }

    public init(
        client: any AccessibilityTextClientProtocol,
        learningHandler: @escaping LearningHandler
    ) {
        self.client = client
        self.learningHandler = learningHandler
    }

    public func begin(_ insertion: AccessibilityInsertion) {
        finishActiveSession()
        activeSession = ActiveSession(insertion: insertion, didChange: false)
        let observed = client.observe(sessionID: insertion.sessionID) { [weak self] event in
            guard let self else { return }
            switch event {
            case .valueChanged:
                self.activeSession?.didChange = true
            case .focusLost:
                self.finishActiveSession()
            }
        }
        if !observed {
            activeSession = nil
            client.stopObserving(sessionID: insertion.sessionID)
        }
    }

    public func finishForRecordingStart() {
        finishActiveSession()
    }

    public func discard(_ insertion: AccessibilityInsertion) {
        client.stopObserving(sessionID: insertion.sessionID)
    }

    private func finishActiveSession() {
        guard let session = activeSession else { return }
        activeSession = nil
        let finalText = session.didChange
            ? client.editedText(sessionID: session.insertion.sessionID)
            : nil
        client.stopObserving(sessionID: session.insertion.sessionID)
        guard let finalText,
              !finalText.isEmpty,
              finalText != session.insertion.originalText else { return }

        let original = session.insertion.originalText
        let bundleID = session.insertion.applicationBundleID
        let learningHandler = self.learningHandler
        Task {
            await learningHandler(original, finalText, bundleID)
        }
    }
}
