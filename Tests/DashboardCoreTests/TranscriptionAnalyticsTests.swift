import Foundation
import XCTest
@testable import DashboardCore

final class TranscriptionAnalyticsTests: XCTestCase {
    func testStorePersistsNewestRecordsWithinConfiguredLimitAndPostsChanges() throws {
        let (store, defaults, key, notifications) = makeStore(maxEntries: 2)
        var changes = 0
        let token = notifications.addObserver(
            forName: .transcriptionAnalyticsDidChange,
            object: store,
            queue: nil
        ) { _ in changes += 1 }
        defer { notifications.removeObserver(token) }

        store.save(.fixture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, startedAt: Date(timeIntervalSince1970: 1)))
        store.save(.fixture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, startedAt: Date(timeIntervalSince1970: 2)))
        store.save(.fixture(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, startedAt: Date(timeIntervalSince1970: 3)))

        XCTAssertEqual(store.records.map(\.startedAt), [Date(timeIntervalSince1970: 3), Date(timeIntervalSince1970: 2)])
        XCTAssertEqual(changes, 3)
        XCTAssertNotNil(defaults.data(forKey: key))

        let reloaded = TranscriptionAnalyticsStore(
            userDefaults: defaults,
            key: key,
            maxEntries: 2,
            notificationCenter: notifications
        )
        XCTAssertEqual(reloaded.records, store.records)
    }

    func testSummaryAggregatesReliabilityLatencyAudioTokensAndCost() {
        let records: [TranscriptionMetric] = [
            .fixture(
                model: "qwen/qwen3-asr-0.6b",
                latencyMilliseconds: 100,
                audioDurationSeconds: 10,
                inputTokens: 80,
                outputTokens: 20,
                totalTokens: 100,
                costUSD: 0.001
            ),
            .fixture(
                model: "qwen/qwen3-asr-0.6b",
                latencyMilliseconds: 200,
                audioDurationSeconds: 20,
                inputTokens: 160,
                outputTokens: 40,
                totalTokens: 200,
                costUSD: 0.002
            ),
            .fixture(
                provider: "Local MLX",
                model: "mlx-community/whisper-large-v3-turbo",
                latencyMilliseconds: 900,
                outcome: .failure,
                errorCategory: "model"
            ),
        ]

        let summary = AnalyticsSummary(records: records)

        XCTAssertEqual(summary.callCount, 3)
        XCTAssertEqual(summary.successCount, 2)
        XCTAssertEqual(summary.successRate, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.averageLatencyMilliseconds, 400, accuracy: 0.000_001)
        XCTAssertEqual(summary.p95LatencyMilliseconds, 900, accuracy: 0.000_001)
        XCTAssertEqual(summary.audioDurationSeconds, 30, accuracy: 0.000_001)
        XCTAssertEqual(summary.inputTokens, 240)
        XCTAssertEqual(summary.outputTokens, 60)
        XCTAssertEqual(summary.totalTokens, 300)
        XCTAssertEqual(summary.costUSD, 0.003, accuracy: 0.000_001)
        XCTAssertTrue(summary.hasTokenData)
        XCTAssertTrue(summary.hasCostData)
    }

    func testSummaryKeepsUnsupportedUsageUnavailableAndGroupsByProviderAndModel() throws {
        let records: [TranscriptionMetric] = [
            .fixture(provider: "Local MLX", model: "Small", latencyMilliseconds: 300),
            .fixture(provider: "OpenRouter", model: "Qwen", latencyMilliseconds: 100, costUSD: 0.004),
        ]

        let summary = AnalyticsSummary(records: records)

        XCTAssertFalse(AnalyticsSummary(records: [records[0]]).hasTokenData)
        XCTAssertFalse(AnalyticsSummary(records: [records[0]]).hasCostData)
        XCTAssertFalse(AnalyticsSummary(records: [records[0]]).hasAudioDurationData)
        XCTAssertEqual(summary.modelSummaries.map(\.displayName), ["Local MLX · Small", "OpenRouter · Qwen"])
        let openRouterCost = try XCTUnwrap(summary.modelSummaries.last?.costUSD)
        XCTAssertEqual(openRouterCost, 0.004, accuracy: 0.000_001)
    }

    func testSummaryDerivesTotalTokensFromCompleteInputAndOutputPair() {
        let completePair = TranscriptionMetric.fixture(inputTokens: 83, outputTokens: 30)
        let inputOnly = TranscriptionMetric.fixture(inputTokens: 10)

        let completeSummary = AnalyticsSummary(records: [completePair])
        let partialSummary = AnalyticsSummary(records: [inputOnly])

        XCTAssertTrue(completeSummary.hasTokenData)
        XCTAssertEqual(completeSummary.totalTokens, 113)
        XCTAssertFalse(partialSummary.hasTokenData)
        XCTAssertEqual(partialSummary.totalTokens, 0)
    }

    func testClearRemovesPersistedRecordsAndPostsChange() {
        let (store, defaults, key, notifications) = makeStore()
        store.save(.fixture())
        var changes = 0
        let token = notifications.addObserver(
            forName: .transcriptionAnalyticsDidChange,
            object: store,
            queue: nil
        ) { _ in changes += 1 }
        defer { notifications.removeObserver(token) }

        store.clear()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertNil(defaults.data(forKey: key))
        XCTAssertEqual(changes, 1)
    }

    private func makeStore(
        maxEntries: Int = 2_000
    ) -> (TranscriptionAnalyticsStore, UserDefaults, String, NotificationCenter) {
        let suite = "TranscriptionAnalyticsTests.\(UUID().uuidString)"
        let key = "metrics"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let notifications = NotificationCenter()
        return (
            TranscriptionAnalyticsStore(
                userDefaults: defaults,
                key: key,
                maxEntries: maxEntries,
                notificationCenter: notifications
            ),
            defaults,
            key,
            notifications
        )
    }
}

private extension TranscriptionMetric {
    static func fixture(
        id: UUID = UUID(),
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        provider: String = "OpenRouter",
        model: String = "qwen/qwen3-asr-1.7b",
        latencyMilliseconds: Double = 100,
        outcome: Outcome = .success,
        errorCategory: String? = nil,
        audioDurationSeconds: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        costUSD: Double? = nil,
        generationID: String? = nil
    ) -> Self {
        .init(
            id: id,
            startedAt: startedAt,
            provider: provider,
            model: model,
            latencyMilliseconds: latencyMilliseconds,
            outcome: outcome,
            errorCategory: errorCategory,
            audioDurationSeconds: audioDurationSeconds,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            costUSD: costUSD,
            generationID: generationID
        )
    }
}
