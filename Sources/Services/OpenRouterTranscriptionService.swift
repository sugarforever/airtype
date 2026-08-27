import Foundation

final class OpenRouterTranscriptionService {
    private let settings: Settings
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func transcribe(audioURL: URL) async throws -> String {
        let apiKey = settings.openrouterTranscriptionApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenRouterTranscriptionError.noAPIKey
        }
        guard Settings.openrouterTranscriptionModels.contains(settings.openrouterTranscriptionModel) else {
            throw OpenRouterTranscriptionError.unsupportedModel(settings.openrouterTranscriptionModel)
        }

        let audioData = try Data(contentsOf: audioURL)
        let format = audioURL.pathExtension.lowercased()
        guard !audioData.isEmpty, !format.isEmpty else {
            throw OpenRouterTranscriptionError.emptyRecording
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.airtype.space", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AirType", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONEncoder().encode(OpenRouterTranscriptionRequest(
            model: settings.openrouterTranscriptionModel,
            inputAudio: .init(data: audioData.base64EncodedString(), format: format)
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterTranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if let response = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                throw OpenRouterTranscriptionError.apiError(response.error.message)
            }
            throw OpenRouterTranscriptionError.httpError(httpResponse.statusCode)
        }

        guard let response = try? JSONDecoder().decode(OpenRouterTranscriptionResponse.self, from: data) else {
            throw OpenRouterTranscriptionError.invalidResponse
        }
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenRouterTranscriptionError.emptyTranscription
        }
        return text
    }
}

private struct OpenRouterTranscriptionRequest: Encodable {
    struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    let model: String
    let inputAudio: InputAudio

    enum CodingKeys: String, CodingKey {
        case model
        case inputAudio = "input_audio"
    }
}

private struct OpenRouterTranscriptionResponse: Decodable {
    let text: String
}

private struct OpenRouterErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let message: String
    }

    let error: ErrorBody
}

enum OpenRouterTranscriptionError: LocalizedError {
    case noAPIKey
    case unsupportedModel(String)
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyRecording
    case emptyTranscription

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter API key not configured"
        case .unsupportedModel(let model):
            return "Unsupported OpenRouter transcription model: \(model)"
        case .invalidResponse:
            return "Invalid response from OpenRouter API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .emptyRecording:
            return "Recording is empty or too short"
        case .emptyTranscription:
            return "OpenRouter returned an empty transcription"
        }
    }
}
