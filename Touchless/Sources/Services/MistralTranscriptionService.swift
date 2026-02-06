import Foundation

/// Mistral Audio Transcription API service
class MistralTranscriptionService {
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Transcribe audio file using Mistral audio transcription API
    func transcribe(audioURL: URL) async throws -> String {
        guard !settings.mistralTranscriptionApiKey.isEmpty else {
            throw MistralTranscriptionError.noAPIKey
        }

        let endpoint = "https://api.mistral.ai/v1/audio/transcriptions"
        guard let url = URL(string: endpoint) else {
            throw MistralTranscriptionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.mistralTranscriptionApiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        let model = settings.mistralTranscriptionModel
        request.httpBody = createMultipartBody(
            audioData: audioData,
            fileName: audioURL.lastPathComponent,
            model: model,
            boundary: boundary
        )

        debugLog("Mistral: Sending request with model \(model), file size: \(audioData.count) bytes")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralTranscriptionError.invalidResponse
        }

        debugLog("Mistral: Response status \(httpResponse.statusCode)")

        if let raw = String(data: data, encoding: .utf8) {
            debugLog("Mistral: Raw response: \(raw.prefix(500))")
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(MistralErrorResponse.self, from: data) {
                throw MistralTranscriptionError.apiError(errorResponse.message)
            }
            throw MistralTranscriptionError.httpError(httpResponse.statusCode)
        }

        let transcription = try JSONDecoder().decode(MistralTranscriptionResponse.self, from: data)
        let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw MistralTranscriptionError.emptyRecording
        }

        return text
    }

    private func createMultipartBody(audioData: Data, fileName: String, model: String, boundary: String) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private struct MistralTranscriptionResponse: Codable {
    let text: String
}

private struct MistralErrorResponse: Codable {
    let message: String
}

enum MistralTranscriptionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Mistral API key not configured"
        case .invalidResponse:
            return "Invalid response from Mistral API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .emptyRecording:
            return "Recording is empty or too short"
        }
    }
}
