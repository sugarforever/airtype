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
        var editedText: String?
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
        activeSession = ActiveSession(insertion: insertion, editedText: nil)
        let sessionID = insertion.sessionID
        let observed = client.observe(sessionID: sessionID) { [weak self] event in
            guard let self else { return }
            guard self.activeSession?.insertion.sessionID == sessionID else {
                return
            }
            switch event {
            case .valueChanged(let editedText):
                guard let editedText else {
                    self.discardActiveSession(expectedSessionID: sessionID)
                    return
                }
                self.activeSession?.editedText = editedText
            case .focusLost:
                self.finishActiveSession(expectedSessionID: sessionID)
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

    private func discardActiveSession(expectedSessionID: UUID) {
        guard activeSession?.insertion.sessionID == expectedSessionID else { return }
        activeSession = nil
        client.stopObserving(sessionID: expectedSessionID)
    }

    private func finishActiveSession(expectedSessionID: UUID? = nil) {
        guard let session = activeSession else { return }
        if let expectedSessionID,
           session.insertion.sessionID != expectedSessionID {
            return
        }
        activeSession = nil
        client.stopObserving(sessionID: session.insertion.sessionID)
        guard let finalText = session.editedText,
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
