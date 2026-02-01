import Foundation

/// OpenAI Whisper/GPT-4o API service for speech-to-text
class WhisperService {
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Transcribe audio file with callback for result
    /// Note: OpenAI transcription API doesn't support true streaming, so this uses standard request
    func transcribeStreaming(
        audioURL: URL,
        onPartialResult: @escaping (String) -> Void
    ) async throws -> String {
        // Use standard transcription (OpenAI transcription API doesn't support SSE streaming)
        let result = try await transcribe(audioURL: audioURL)
        onPartialResult(result)
        return result
    }

    /// Transcribe audio file (non-streaming)
    func transcribe(audioURL: URL) async throws -> String {
        guard !settings.openaiApiKey.isEmpty else {
            throw WhisperError.noAPIKey
        }

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openaiApiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let body = createMultipartBody(
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            model: settings.openaiModel,
            boundary: boundary
        )
        request.httpBody = body

        debugLog("OpenAI: Sending request with model \(settings.openaiModel)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        debugLog("OpenAI: Response status \(httpResponse.statusCode)")

        // Debug: log raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            debugLog("OpenAI: Raw response: \(rawResponse.prefix(500))")
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw WhisperError.apiError(errorResponse.error.message)
            }
            throw WhisperError.httpError(httpResponse.statusCode)
        }

        let transcription = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        debugLog("OpenAI: Decoded text: '\(transcription.text)'")
        return transcription.text
    }

    // MARK: - Multipart Body Creation

    private func createMultipartBody(audioData: Data, fileName: String, model: String, boundary: String) -> Data {
        var body = Data()

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        // Audio file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }

}

// MARK: - Response Types

struct TranscriptionResponse: Codable {
    let text: String
}

struct TranscriptStreamEvent: Codable {
    let type: String?
    let delta: String?
    let text: String?
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
}

struct OpenAIError: Codable {
    let message: String
    let type: String?
    let code: String?
}

// MARK: - Errors

enum WhisperError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from Whisper API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        }
    }
}
