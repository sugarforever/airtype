import Foundation

final class OpenRouterTranscriptionService {
    private let settings: Settings
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await transcribeWithMetadata(audioURL: audioURL).text
    }

    func transcribeWithMetadata(audioURL: URL) async throws -> OpenRouterTranscriptionResult {
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
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.airtype.space", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AirType", forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONEncoder().encode(OpenRouterTranscriptionRequest(
            model: settings.openrouterTranscriptionModel,
            inputAudio: .init(data: audioData.base64EncodedString(), format: format)
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenRouterTranscriptionError.timeout
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterTranscriptionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 408 || httpResponse.statusCode == 504 {
                throw OpenRouterTranscriptionError.timeout
            }
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
        return OpenRouterTranscriptionResult(
            text: text,
            usage: response.usage,
            generationID: httpResponse.value(forHTTPHeaderField: "X-Generation-Id")
        )
    }
}

struct OpenRouterTranscriptionResult: Equatable, Sendable {
    let text: String
    let usage: OpenRouterTranscriptionUsage?
    let generationID: String?
}

struct OpenRouterTranscriptionUsage: Decodable, Equatable, Sendable {
    let seconds: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case seconds
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case cost
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
    let usage: OpenRouterTranscriptionUsage?
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
    case timeout
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
        case .timeout:
            return "OpenRouter transcription timed out. Please try again or use a shorter recording."
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
