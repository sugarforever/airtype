import Foundation
#if SWIFT_PACKAGE
import VocabularyCore
#endif

struct QwenASRAdapter: LocalASRAdapter {
    let model: LocalMLXModel

    func transcribe(
        audioURL: URL,
        language: LocalMLXLanguage,
        computeMode: LocalMLXComputeMode,
        context: TranscriptionContext
    ) async throws -> String {
        _ = computeMode // reserved for future runtime tuning flags
        return try await MLXAudioRunner.transcribe(
            modelID: model.repoID,
            audioPath: audioURL.path,
            languageCode: languageCode(for: language),
            context: context
        )
    }

    private func languageCode(for language: LocalMLXLanguage) -> String? {
        switch language {
        case .auto: return nil
        case .english: return "en"
        case .chinese: return "zh"
        }
    }
}
