import Foundation

struct OpenRouterKeyUsage: Decodable, Equatable, Sendable {
    let total: Double
    let daily: Double
    let weekly: Double
    let monthly: Double
    let limit: Double?
    let limitRemaining: Double?
    let limitReset: String?
    let isFreeTier: Bool
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case total = "usage"
        case daily = "usage_daily"
        case weekly = "usage_weekly"
        case monthly = "usage_monthly"
        case limit
        case limitRemaining = "limit_remaining"
        case limitReset = "limit_reset"
        case isFreeTier = "is_free_tier"
        case expiresAt = "expires_at"
    }
}

final class OpenRouterKeyUsageService {
    private let settings: Settings
    private let session: URLSession

    init(settings: Settings = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func fetch() async throws -> OpenRouterKeyUsage {
        let apiKey = settings.openrouterTranscriptionApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw OpenRouterKeyUsageError.noAPIKey
        }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://www.airtype.space", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AirType", forHTTPHeaderField: "X-OpenRouter-Title")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterKeyUsageError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw OpenRouterKeyUsageError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenRouterKeyUsageError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(OpenRouterKeyUsageEnvelope.self, from: data) else {
            throw OpenRouterKeyUsageError.invalidResponse
        }
        return envelope.data
    }
}

private struct OpenRouterKeyUsageEnvelope: Decodable {
    let data: OpenRouterKeyUsage
}

enum OpenRouterKeyUsageError: LocalizedError {
    case noAPIKey
    case unauthorized
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenRouter API key not configured"
        case .unauthorized:
            return "OpenRouter rejected the API key"
        case .invalidResponse:
            return "Invalid usage response from OpenRouter"
        case .httpError(let status):
            return "OpenRouter usage request failed (HTTP \(status))"
        }
    }
}
