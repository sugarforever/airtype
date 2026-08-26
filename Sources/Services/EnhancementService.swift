import Foundation
#if SWIFT_PACKAGE
import CorrectionLearningCore
import VocabularyCore
#endif

/// OpenAI GPT service for speech-to-text error correction
/// Fixes transcription errors while preserving the speaker's original words
class EnhancementService {
    private let settings: Settings
    private let session: URLSession
    private let learningService: CorrectionLearningService?
    private let vocabularyRepository: VocabularyRepository?
    private let promptBuilder: EnhancementPromptBuilder
    private let vocabularyPromptBuilder: VocabularyPromptBuilder

    init(
        settings: Settings = .shared,
        session: URLSession = .shared,
        learningService: CorrectionLearningService? = nil,
        vocabularyRepository: VocabularyRepository? = nil,
        promptBuilder: EnhancementPromptBuilder = EnhancementPromptBuilder(),
        vocabularyPromptBuilder: VocabularyPromptBuilder = VocabularyPromptBuilder()
    ) {
        self.settings = settings
        self.session = session
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

        let correctionExamples = await learningService?.examples(for: text) ?? []
        let vocabularyTerms = await vocabularyRepository?.promptTerms(tokenBudget: 300) ?? []
        let vocabularySection = vocabularyPromptBuilder.section(terms: vocabularyTerms)
        return try await performCompletion(
            text: text,
            systemPrompt: promptBuilder.prompt(
                examples: correctionExamples,
                vocabularySection: vocabularySection
            ),
            fallbackToOriginalOnEmpty: true
        )
    }

    /// Sends a small request through the same path used by Enhancement so users
    /// can validate credentials, endpoint, model, and response compatibility.
    func testConfiguration() async throws -> String {
        try validateConfiguration()
        return try await performCompletion(
            text: "Airtype works well.",
            systemPrompt: promptBuilder.prompt(examples: [], vocabularySection: ""),
            fallbackToOriginalOnEmpty: false
        )
    }

    private func performCompletion(
        text: String,
        systemPrompt: String,
        fallbackToOriginalOnEmpty: Bool
    ) async throws -> String {
        try validateConfiguration()
        try Task.checkCancellation()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let enhancementModel = settings.currentEnhancementModel
        let systemRole = enhancementModel.hasPrefix("gpt-5") ? "developer" : "system"
        let supportsTemperature = !enhancementModel.contains("mini") && !enhancementModel.contains("nano")

        var request = URLRequest(url: try completionURL())
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.currentEnhancementApiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: enhancementModel,
            messages: [
                ChatMessage(role: systemRole, content: systemPrompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: supportsTemperature ? 0.1 : nil,
            maxCompletionTokens: 2048
        ))

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
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

            switch httpResponse.statusCode {
            case 401, 403:
                throw EnhancementError.authenticationFailed(provider: settings.enhancementProvider.rawValue, statusCode: httpResponse.statusCode)
            case 404:
                throw EnhancementError.endpointOrModelNotFound(
                    provider: settings.enhancementProvider.rawValue,
                    model: enhancementModel,
                    statusCode: httpResponse.statusCode
                )
            case 429:
                throw EnhancementError.apiError("Rate limit exceeded")
            case 500, 502, 503:
                throw EnhancementError.apiError("Server error. Using original text.")
            default:
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    throw EnhancementError.apiError(errorResponse.error.message)
                }
                throw EnhancementError.httpError(httpResponse.statusCode)
            }
        }

        let completion: ChatCompletionResponse
        do {
            completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw EnhancementError.incompatibleResponse(provider: settings.enhancementProvider.rawValue)
        }
        guard let enhancedText = completion.choices.first?.message.content else {
            throw EnhancementError.noContent
        }

        let result = enhancedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If enhancement returned empty, use original
        if result.isEmpty {
            if fallbackToOriginalOnEmpty {
                return trimmedText
            }
            throw EnhancementError.noContent
        }

        return result
    }

    private func validateConfiguration() throws {
        if settings.enhancementProvider.requiresApiKey && settings.currentEnhancementApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EnhancementError.noAPIKey
        }
        if settings.currentEnhancementModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EnhancementError.invalidConfiguration("Enter a model name before testing.")
        }
        _ = try completionURL()
    }

    private func completionURL() throws -> URL {
        let baseURL = settings.currentEnhancementBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard
            !baseURL.isEmpty,
            let url = URL(string: "\(baseURL)/chat/completions"),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw EnhancementError.invalidConfiguration("Enter a valid HTTP or HTTPS Base URL before testing.")
        }
        return url
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
    case invalidConfiguration(String)
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case authenticationFailed(provider: String, statusCode: Int)
    case endpointOrModelNotFound(provider: String, model: String, statusCode: Int)
    case incompatibleResponse(provider: String)
    case noContent
    case networkTimeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Enhancement API key not configured"
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return "Invalid response from GPT API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Enhancement error: \(message)"
        case .authenticationFailed(let provider, let statusCode):
            return "\(provider) rejected the API key (HTTP \(statusCode)). Check the key and account permissions."
        case .endpointOrModelNotFound(let provider, let model, let statusCode):
            return "\(provider) could not find the configured endpoint or model “\(model)” (HTTP \(statusCode)). Check the Base URL and Model fields."
        case .incompatibleResponse(let provider):
            return "\(provider) responded successfully, but its response is not OpenAI chat-completions compatible."
        case .noContent:
            return "The provider returned an empty completion."
        case .networkTimeout:
            return "Enhancement timed out. Text used without enhancement."
        }
    }
}
