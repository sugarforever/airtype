import Foundation
#if SWIFT_PACKAGE
import CorrectionLearningCore
import VocabularyCore
#endif

/// OpenAI GPT service for speech-to-text error correction
/// Fixes transcription errors while preserving the speaker's original words
class EnhancementService {
    private let settings: Settings
    private let learningService: CorrectionLearningService?
    private let vocabularyRepository: VocabularyRepository?
    private let promptBuilder: EnhancementPromptBuilder
    private let vocabularyPromptBuilder: VocabularyPromptBuilder

    init(
        settings: Settings = .shared,
        learningService: CorrectionLearningService? = nil,
        vocabularyRepository: VocabularyRepository? = nil,
        promptBuilder: EnhancementPromptBuilder = EnhancementPromptBuilder(),
        vocabularyPromptBuilder: VocabularyPromptBuilder = VocabularyPromptBuilder()
    ) {
        self.settings = settings
        self.learningService = learningService
        self.vocabularyRepository = vocabularyRepository
        self.promptBuilder = promptBuilder
        self.vocabularyPromptBuilder = vocabularyPromptBuilder
    }

    /// Correct transcription errors using GPT with timeout and error handling
    /// Preserves original speech while fixing ASR mistakes
    func enhance(text: String) async throws -> String {
        guard settings.enhancementEnabled else {
            return text
        }

        // Skip enhancement for very short text
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.count < 3 {
            return trimmedText
        }

        guard !settings.currentEnhancementApiKey.isEmpty || !settings.enhancementProvider.requiresApiKey else {
            throw EnhancementError.noAPIKey
        }

        try Task.checkCancellation()

        let baseURL = settings.currentEnhancementBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let url = URL(string: "\(baseURL)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.currentEnhancementApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60  // 1 minute timeout

        let enhancementModel = settings.currentEnhancementModel

        // GPT-5 models use "developer" role instead of "system"
        let systemRole = enhancementModel.hasPrefix("gpt-5") ? "developer" : "system"

        // GPT-5-mini and nano don't support custom temperature
        let supportsTemperature = !enhancementModel.contains("mini") && !enhancementModel.contains("nano")
        let correctionExamples = await learningService?.examples(for: text) ?? []
        let vocabularyTerms = await vocabularyRepository?.promptTerms(tokenBudget: 300) ?? []
        let vocabularySection = vocabularyPromptBuilder.section(terms: vocabularyTerms)

        let requestBody = ChatCompletionRequest(
            model: enhancementModel,
            messages: [
                ChatMessage(
                    role: systemRole,
                    content: promptBuilder.prompt(
                        examples: correctionExamples,
                        vocabularySection: vocabularySection
                    )
                ),
                ChatMessage(role: "user", content: text)
            ],
            temperature: supportsTemperature ? 0.1 : nil,
            maxCompletionTokens: 2048
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
            debugLog("Enhancement: Error response status \(httpResponse.statusCode), \(data.count) bytes")

            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                let message = errorResponse.error.message
                // Detect specific error types
                if message.lowercased().contains("rate limit") {
                    throw EnhancementError.apiError("Rate limit exceeded. Text will be used without enhancement.")
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

}

// MARK: - Request/Response Types
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxCompletionTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxCompletionTokens = "max_completion_tokens"
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
