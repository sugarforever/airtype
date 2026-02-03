import Foundation

/// OpenAI GPT service for text enhancement
class EnhancementService {
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Enhance transcribed text using GPT with timeout and error handling
    func enhance(text: String) async throws -> String {
        guard settings.enhancementEnabled else {
            return text
        }

        // Skip enhancement for very short text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.count < 3 {
            return trimmedText
        }

        guard !settings.openaiApiKey.isEmpty else {
            throw EnhancementError.noAPIKey
        }

        let baseURL = settings.openaiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.openaiApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // 1 minute timeout

        let requestBody = ChatCompletionRequest(
            model: settings.enhancementModel,
            messages: [
                ChatMessage(role: "system", content: enhancementPrompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: 0.3,
            maxTokens: 2048
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw EnhancementError.networkTimeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw EnhancementError.apiError("No internet connection")
            default:
                throw EnhancementError.apiError("Network error: \(error.localizedDescription)")
            }
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnhancementError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let message = errorResponse.error.message

                // Detect specific error types
                if message.lowercased().contains("rate limit") {
                    throw EnhancementError.apiError("Rate limit exceeded. Text will be used without enhancement.")
                }
                if message.lowercased().contains("model") {
                    throw EnhancementError.apiError("Model '\(settings.enhancementModel)' not available. Please check Settings.")
                }

                throw EnhancementError.apiError(message)
            }

            // Handle common HTTP status codes
            switch httpResponse.statusCode {
            case 401:
                throw EnhancementError.apiError("Invalid API key")
            case 429:
                throw EnhancementError.apiError("Rate limit exceeded")
            case 500, 502, 503:
                throw EnhancementError.apiError("Server error. Using original text.")
            default:
                throw EnhancementError.httpError(httpResponse.statusCode)
            }
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let enhancedText = completion.choices.first?.message.content else {
            throw EnhancementError.noContent
        }

        let result = enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If enhancement returned empty, use original
        if result.isEmpty {
            return trimmedText
        }

        return result
    }

    private var enhancementPrompt: String {
        """
        You are a text enhancement assistant. Your task is to clean up transcribed speech and make it ready for use.

        Rules:
        1. Remove filler words: um, uh, like, you know, basically, actually, literally, kind of, sort of, I mean
        2. Remove false starts and repetitions (when someone restarts a sentence)
        3. Fix self-corrections (use the corrected version only)
        4. Add proper punctuation and capitalization
        5. Keep the original meaning and tone intact
        6. Do NOT add new information or change the intent
        7. Do NOT use formal language unless the original was formal
        8. Keep it concise and natural

        Return ONLY the cleaned text, nothing else. No explanations, no quotes around the text.
        """
    }
}

// MARK: - Request/Response Types
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ChatMessage
}

// MARK: - Errors
enum EnhancementError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent
    case networkTimeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured"
        case .invalidResponse:
            return "Invalid response from GPT API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Enhancement error: \(message)"
        case .noContent:
            return "No content in API response"
        case .networkTimeout:
            return "Enhancement timed out. Text used without enhancement."
        }
    }
}
