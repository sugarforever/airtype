import Foundation
#if SWIFT_PACKAGE
import VocabularyCore
#endif

final class MLXTranscriptionService {
    func transcribe(
        audioURL: URL,
        model: LocalMLXModel,
        language: LocalMLXLanguage,
        computeMode: LocalMLXComputeMode,
        installedModelIDs: Set<String>,
        context: TranscriptionContext = .empty
    ) async throws -> String {
        let startTime = Date()

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw LocalMLXTranscriptionError.invalidAudioFile
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw LocalMLXTranscriptionError.emptyRecording
        }

        guard installedModelIDs.contains(model.rawValue) else {
            throw LocalMLXTranscriptionError.modelNotInstalled(model.rawValue)
        }

        let adapterLoadStart = Date()
        let adapter = adapter(for: model)
        debugLog("MLX local adapter selected: \(type(of: adapter)), model=\(model.rawValue), loadMs=\(Int(Date().timeIntervalSince(adapterLoadStart) * 1000))")

        let text = try await adapter.transcribe(
            audioURL: audioURL,
            language: language,
            computeMode: computeMode,
            context: context
        )
        debugLog("MLX local transcription completed: model=\(model.rawValue), totalMs=\(Int(Date().timeIntervalSince(startTime) * 1000))")
        return text
    }

    private func adapter(for model: LocalMLXModel) -> any LocalASRAdapter {
        switch model {
        case .qwen3ASR06B4bit, .qwen3ASR17B:
            return QwenASRAdapter(model: model)
        }
    }
}

enum LocalMLXTranscriptionError: LocalizedError {
    case modelNotInstalled(String)
    case modelFileMissing(String)
    case runtimeUnavailable(model: String, language: String, computeMode: String)
    case runtimeDependencyMissing(String)
    case runtimeExecutionFailed(String)
    case invalidAudioFile
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let model):
            return "\(model) is not installed. Install it in Settings > Voice Input."
        case .modelFileMissing(let message):
            return message
        case .runtimeUnavailable(let model, let language, let computeMode):
            return "MLX local runtime not wired yet for model \(model) (\(language), \(computeMode))."
        case .runtimeDependencyMissing(let message):
            return message
        case .runtimeExecutionFailed(let details):
            return "Local ASR runtime failed: \(details)"
        case .invalidAudioFile:
            return "Invalid audio file."
        case .emptyRecording:
            return "No speech detected. Please try again."
        }
    }
}
