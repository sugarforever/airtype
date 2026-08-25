import Foundation
#if SWIFT_PACKAGE
import VocabularyCore
#endif

protocol LocalASRAdapter {
    func transcribe(
        audioURL: URL,
        language: LocalMLXLanguage,
        computeMode: LocalMLXComputeMode,
        context: TranscriptionContext
    ) async throws -> String
}
