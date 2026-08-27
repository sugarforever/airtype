#if canImport(Airtype)
import Foundation
import XCTest
import DashboardCore
@testable import Airtype

final class TranscriptionAnalyticsInstrumentationTests: XCTestCase {
    func testSuccessfulAttemptStoresProviderModelTimingAndOpenRouterUsage() throws {
        var saved: [TranscriptionMetric] = []
        let attempt = TranscriptionAttempt(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            provider: "OpenRouter",
            model: "qwen/qwen3-asr-1.7b",
            audioDurationSeconds: 8.5,
            elapsedMilliseconds: { 275 },
            save: { saved.append($0) }
        )

        attempt.succeed(metadata: .init(
            audioDurationSeconds: 9.2,
            inputTokens: 83,
            outputTokens: 30,
            totalTokens: 113,
            costUSD: 0.000508,
            generationID: "gen-airtype-123"
        ))

        let metric = try XCTUnwrap(saved.first)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(metric.provider, "OpenRouter")
        XCTAssertEqual(metric.model, "qwen/qwen3-asr-1.7b")
        XCTAssertEqual(metric.latencyMilliseconds, 275)
        XCTAssertEqual(metric.outcome, .success)
        XCTAssertEqual(metric.audioDurationSeconds, 9.2)
        XCTAssertEqual(metric.inputTokens, 83)
        XCTAssertEqual(metric.outputTokens, 30)
        XCTAssertEqual(metric.totalTokens, 113)
        XCTAssertEqual(metric.costUSD, 0.000508)
        XCTAssertEqual(metric.generationID, "gen-airtype-123")
    }

    func testFailedAttemptStoresSanitizedCategoryWithoutErrorText() throws {
        var saved: [TranscriptionMetric] = []
        let attempt = TranscriptionAttempt(
            provider: "OpenRouter",
            model: "qwen/qwen3-asr-0.6b",
            audioDurationSeconds: 4,
            elapsedMilliseconds: { 1_200 },
            save: { saved.append($0) }
        )

        attempt.fail(URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "secret request detail"]))

        let metric = try XCTUnwrap(saved.first)
        XCTAssertEqual(metric.outcome, .failure)
        XCTAssertEqual(metric.errorCategory, "timeout")
        XCTAssertFalse(String(describing: metric).contains("secret request detail"))
    }

    func testAttemptCanOnlyCompleteOnce() {
        var saved: [TranscriptionMetric] = []
        let attempt = TranscriptionAttempt(
            provider: "Local MLX",
            model: "Small",
            audioDurationSeconds: nil,
            elapsedMilliseconds: { 10 },
            save: { saved.append($0) }
        )

        attempt.succeed()
        attempt.fail(URLError(.networkConnectionLost))

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.outcome, .success)
    }

    func testProviderErrorsUseSanitizedUsefulCategories() {
        let cases: [(Error, String)] = [
            (WhisperError.networkTimeout, "timeout"),
            (ElevenLabsError.noAPIKey, "authentication"),
            (MistralTranscriptionError.emptyRecording, "empty"),
            (LocalMLXTranscriptionError.modelNotInstalled("private model path"), "model"),
        ]

        for (error, expectedCategory) in cases {
            var saved: [TranscriptionMetric] = []
            let attempt = TranscriptionAttempt(
                provider: "Test",
                model: "Test",
                audioDurationSeconds: nil,
                elapsedMilliseconds: { 1 },
                save: { saved.append($0) }
            )

            attempt.fail(error)

            XCTAssertEqual(saved.first?.errorCategory, expectedCategory)
            XCTAssertFalse(String(describing: saved.first).contains("private model path"))
        }
    }
}
#endif
