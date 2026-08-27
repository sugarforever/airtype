import Foundation
#if SWIFT_PACKAGE
import DashboardCore
#endif

struct TranscriptionUsageMetadata: Equatable, Sendable {
    let audioDurationSeconds: Double?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let costUSD: Double?
    let generationID: String?

    init(
        audioDurationSeconds: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        costUSD: Double? = nil,
        generationID: String? = nil
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.generationID = generationID
    }
}

final class TranscriptionAttempt {
    private let startedAt: Date
    private let provider: String
    private let model: String
    private let audioDurationSeconds: Double?
    private let elapsedMilliseconds: () -> Double
    private let save: (TranscriptionMetric) -> Void
    private let lock = NSLock()
    private var completed = false

    init(
        startedAt: Date = Date(),
        provider: String,
        model: String,
        audioDurationSeconds: Double?,
        elapsedMilliseconds: @escaping () -> Double,
        save: @escaping (TranscriptionMetric) -> Void
    ) {
        self.startedAt = startedAt
        self.provider = provider
        self.model = model
        self.audioDurationSeconds = audioDurationSeconds
        self.elapsedMilliseconds = elapsedMilliseconds
        self.save = save
    }

    convenience init(
        provider: String,
        model: String,
        audioDurationSeconds: Double?,
        store: TranscriptionAnalyticsStore = .shared
    ) {
        let clock = ContinuousClock()
        let start = clock.now
        self.init(
            provider: provider,
            model: model,
            audioDurationSeconds: audioDurationSeconds,
            elapsedMilliseconds: {
                let duration = start.duration(to: clock.now)
                return Double(duration.components.seconds) * 1_000
                    + Double(duration.components.attoseconds) / 1_000_000_000_000_000
            },
            save: store.save
        )
    }

    func succeed(metadata: TranscriptionUsageMetadata? = nil) {
        complete(
            outcome: .success,
            errorCategory: nil,
            metadata: metadata
        )
    }

    func fail(_ error: Error) {
        complete(
            outcome: .failure,
            errorCategory: Self.category(for: error),
            metadata: nil
        )
    }

    private func complete(
        outcome: TranscriptionMetric.Outcome,
        errorCategory: String?,
        metadata: TranscriptionUsageMetadata?
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        save(TranscriptionMetric(
            startedAt: startedAt,
            provider: provider,
            model: model,
            latencyMilliseconds: max(0, elapsedMilliseconds()),
            outcome: outcome,
            errorCategory: errorCategory,
            audioDurationSeconds: metadata?.audioDurationSeconds ?? audioDurationSeconds,
            inputTokens: metadata?.inputTokens,
            outputTokens: metadata?.outputTokens,
            totalTokens: metadata?.totalTokens,
            costUSD: metadata?.costUSD,
            generationID: metadata?.generationID
        ))
    }

    private static func category(for error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "timeout"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed:
                return "network"
            default: return "network"
            }
        }
        if let openRouterError = error as? OpenRouterTranscriptionError {
            switch openRouterError {
            case .timeout: return "timeout"
            case .noAPIKey: return "authentication"
            case .emptyRecording, .emptyTranscription: return "empty"
            case .unsupportedModel: return "model"
            case .invalidResponse, .httpError, .apiError: return "provider"
            }
        }
        if let whisperError = error as? WhisperError {
            switch whisperError {
            case .noAPIKey: return "authentication"
            case .networkTimeout: return "timeout"
            case .emptyRecording: return "empty"
            case .invalidAudioFile, .audioProcessingFailed: return "audio"
            case .fileTooLarge: return "file_size"
            case .httpError(let status): return category(forHTTPStatus: status)
            case .invalidResponse, .apiError: return "provider"
            }
        }
        if let elevenLabsError = error as? ElevenLabsError {
            switch elevenLabsError {
            case .noAPIKey: return "authentication"
            case .emptyTranscription: return "empty"
            case .httpError(let status): return category(forHTTPStatus: status)
            case .invalidResponse, .apiError: return "provider"
            }
        }
        if let mistralError = error as? MistralTranscriptionError {
            switch mistralError {
            case .noAPIKey: return "authentication"
            case .emptyRecording: return "empty"
            case .httpError(let status): return category(forHTTPStatus: status)
            case .invalidResponse, .apiError: return "provider"
            }
        }
        if let localError = error as? LocalMLXTranscriptionError {
            switch localError {
            case .modelNotInstalled, .modelFileMissing: return "model"
            case .emptyRecording: return "empty"
            case .invalidAudioFile: return "audio"
            case .runtimeUnavailable, .runtimeDependencyMissing, .runtimeExecutionFailed: return "runtime"
            }
        }
        return "unknown"
    }

    private static func category(forHTTPStatus status: Int) -> String {
        switch status {
        case 401, 403: return "authentication"
        case 408, 504: return "timeout"
        case 429: return "rate_limit"
        default: return "provider"
        }
    }
}
