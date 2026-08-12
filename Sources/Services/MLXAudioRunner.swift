import Foundation
import MLXAudioCore
import MLXAudioSTT

enum MLXAudioRunner {
    static func installModel(modelID: String) async throws {
        if modelID.contains("Qwen3-ASR") {
            _ = try await Qwen3ASRModel.fromPretrained(modelID)
            return
        }
        throw LocalMLXTranscriptionError.runtimeExecutionFailed("Unsupported model: \(modelID)")
    }

    static func removeModel(modelID: String) {
        let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/hub/mlx-audio", isDirectory: true)
        let modelDir = cacheRoot?.appendingPathComponent(modelID.replacingOccurrences(of: "/", with: "_"), isDirectory: true)
        if let modelDir {
            try? FileManager.default.removeItem(at: modelDir)
        }
    }

    static func transcribe(
        modelID: String,
        audioPath: String,
        languageCode: String?
    ) async throws -> String {
        let audioURL = URL(fileURLWithPath: audioPath)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)

        let language = normalizeLanguage(languageCode)

        do {
            if modelID.contains("Qwen3-ASR") {
                let model = try await Qwen3ASRModel.fromPretrained(modelID)
                let output = model.generate(audio: audio, language: language)
                let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    throw LocalMLXTranscriptionError.emptyRecording
                }
                return text
            }

            throw LocalMLXTranscriptionError.runtimeUnavailable(
                model: modelID,
                language: languageCode ?? "auto",
                computeMode: "balanced"
            )
        } catch let error as LocalMLXTranscriptionError {
            throw error
        } catch {
            throw LocalMLXTranscriptionError.runtimeExecutionFailed(error.localizedDescription)
        }
    }

    private static func normalizeLanguage(_ languageCode: String?) -> String? {
        guard let code = languageCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !code.isEmpty else {
            return nil
        }

        switch code {
        case "en", "english":
            return "English"
        case "zh", "zh-cn", "chinese":
            return "Chinese"
        default:
            return languageCode
        }
    }
}
