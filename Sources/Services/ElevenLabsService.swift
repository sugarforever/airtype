import Foundation
#if SWIFT_PACKAGE
import CorrectionLearningCore
import VocabularyCore
#endif

/// ElevenLabs Speech-to-Text API service
class ElevenLabsService {
    private let settings: Settings
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    /// Transcribe audio file using ElevenLabs Scribe API
    func transcribe(audioURL: URL, context: TranscriptionContext = .empty) async throws -> String {
        guard !settings.elevenlabsApiKey.isEmpty else {
            throw ElevenLabsError.noAPIKey
        }

        let url = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.elevenlabsApiKey, forHTTPHeaderField: "xi-api-key")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        debugLog("ElevenLabs: Audio data size: \(audioData.count) bytes")

        let body = createMultipartBody(
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            modelId: settings.elevenlabsModel,
            boundary: boundary,
            context: context
        )
        request.httpBody = body

        debugLog("ElevenLabs: Request body size: \(body.count) bytes")
        debugLog("ElevenLabs: Sending request with model \(settings.elevenlabsModel)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ElevenLabsError.invalidResponse
        }

        debugLog("ElevenLabs: Response status \(httpResponse.statusCode)")

        debugLog("ElevenLabs: Response body \(data.count) bytes")

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? [String: Any],
               let message = detail["message"] as? String {
                throw ElevenLabsError.apiError(message)
            }
            throw ElevenLabsError.httpError(httpResponse.statusCode)
        }

        let transcription = try JSONDecoder().decode(ElevenLabsTranscriptionResponse.self, from: data)
        debugLog(PrivacySafeDiagnostics.textEvent(
            label: "ElevenLabs transcription decoded",
            characterCount: transcription.text.count
        ))
        return transcription.text
    }

    func createMultipartBody(audioData: Data, fileName: String, modelId: String, boundary: String, context: TranscriptionContext = .empty) -> Data {
        var body = Data()

        // Model ID field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(modelId)\r\n".data(using: .utf8)!)

        body.append(context.multipartData(for: .elevenlabs, model: modelId, boundary: boundary))

        // Audio file - use application/octet-stream to let API auto-detect format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

// MARK: - Response Types

struct ElevenLabsTranscriptionResponse: Codable {
    let text: String
    let languageCode: String?
    let languageProbability: Double?
    let words: [ElevenLabsWord]?

    enum CodingKeys: String, CodingKey {
        case text
        case languageCode = "language_code"
        case languageProbability = "language_probability"
        case words
    }
}

struct ElevenLabsWord: Codable {
    let text: String
    let start: Double?
    let end: Double?
    let type: String?
    let speakerId: String?

    enum CodingKeys: String, CodingKey {
        case text, start, end, type
        case speakerId = "speaker_id"
    }
}

// MARK: - Errors

enum ElevenLabsError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "ElevenLabs API key not configured"
        case .invalidResponse:
            return "Invalid response from ElevenLabs API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
