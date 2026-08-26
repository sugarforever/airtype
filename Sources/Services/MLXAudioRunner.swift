import Foundation
import MLXAudioCore
import MLXAudioSTT
#if SWIFT_PACKAGE
import VocabularyCore
#endif

#if DEBUG
/// Explicit, process-scoped opt-in: these diagnostics contain vocabulary and speech text.
/// No files are written here; the diagnostic launch captures stderr in a private local file.
enum LocalASRDiagnostics {
    static func line(event: String, fields: [String: String], enabled: Bool) -> String? {
        guard enabled,
              let data = try? JSONSerialization.data(
                withJSONObject: ["event": event, "fields": fields], options: [.sortedKeys]
              ) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func log(event: String, fields: [String: String]) {
        guard let line = line(
            event: event, fields: fields,
            enabled: ProcessInfo.processInfo.environment["AIRTYPE_ASR_DIAGNOSTICS"] == "1"
        ) else { return }
        debugLog("ASR_DIAGNOSTIC \(line)")
    }
}
#endif

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
        languageCode: String?,
        context: TranscriptionContext = .empty
    ) async throws -> String {
        let audioURL = URL(fileURLWithPath: audioPath)
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16_000)

        let language = normalizeLanguage(languageCode)

        do {
            if modelID.contains("Qwen3-ASR") {
                let model = try await Qwen3ASRModel.fromPretrained(modelID)
                let qwenContext = context.qwenContext
#if DEBUG
                let requestID = UUID().uuidString
                LocalASRDiagnostics.log(event: "qwen_request", fields: [
                    "request_id": requestID,
                    "model": modelID,
                    "language": language ?? "auto",
                    "context": qwenContext,
                    "context_utf8_bytes": String(qwenContext.utf8.count),
                    "snapshot_term_count": String(context.terms.count)
                ])
#endif
                let output = model.generate(audio: audio, context: qwenContext, language: language)
#if DEBUG
                LocalASRDiagnostics.log(event: "qwen_result", fields: [
                    "request_id": requestID,
                    "raw_text": output.text,
                    "prompt_tokens": String(output.promptTokens),
                    "generation_tokens": String(output.generationTokens)
                ])
#endif
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
