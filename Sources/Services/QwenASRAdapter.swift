import Foundation

struct QwenASRAdapter: LocalASRAdapter {
    let model: LocalMLXModel

    func transcribe(
        audioURL: URL,
        language: LocalMLXLanguage,
        computeMode: LocalMLXComputeMode
    ) async throws -> String {
        _ = computeMode // reserved for future runtime tuning flags
        return try await MLXAudioRunner.transcribe(
            modelID: modelID,
            audioPath: audioURL.path,
            languageCode: languageCode(for: language)
        )
    }

    private var modelID: String {
        switch model {
        case .qwen3ASR06B4bit:
            return "mlx-community/Qwen3-ASR-0.6B-4bit"
        case .qwen3ASR17B:
            return "mlx-community/Qwen3-ASR-1.7B-4bit"
        }
    }

    private func languageCode(for language: LocalMLXLanguage) -> String? {
        switch language {
        case .auto: return nil
        case .english: return "en"
        case .chinese: return "zh"
        }
    }
}
