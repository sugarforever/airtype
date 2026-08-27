import Foundation
import XCTest
@testable import DashboardCore

@MainActor
@available(macOS 14.0, *)
final class AnalyticsPageModelTests: XCTestCase {
    func testModelLoadsLocalRecordsAndRespondsToStoreChanges() async {
        let (store, _) = makeStore()
        store.save(.fixture(provider: "Local MLX", model: "Small"))
        let model = AnalyticsPageModel(store: store)

        XCTAssertEqual(model.summary.callCount, 1)
        XCTAssertEqual(model.recentRecords.first?.provider, "Local MLX")

        store.save(.fixture(provider: "OpenRouter", model: "Qwen"))
        await Task.yield()

        XCTAssertEqual(model.summary.callCount, 2)
        XCTAssertEqual(model.recentRecords.first?.provider, "OpenRouter")
    }

    func testClearRequiresConfirmationAndRemovesLocalMetrics() {
        let (store, _) = makeStore()
        store.save(.fixture())
        let model = AnalyticsPageModel(store: store)

        model.requestClear()
        XCTAssertTrue(model.isClearConfirmationPresented)
        XCTAssertEqual(model.summary.callCount, 1)

        model.confirmClear()

        XCTAssertFalse(model.isClearConfirmationPresented)
        XCTAssertEqual(model.summary.callCount, 0)
        XCTAssertTrue(store.records.isEmpty)
    }

    func testRemoteRefreshPublishesOpenRouterKeyUsage() async {
        let expected = OpenRouterKeyUsageSnapshot(
            total: 25.5,
            daily: 1.25,
            weekly: 7.5,
            monthly: 20,
            limit: 100,
            limitRemaining: 74.5,
            limitReset: "monthly"
        )
        let model = AnalyticsPageModel(store: makeStore().0) { expected }

        await model.refreshOpenRouterUsage()

        XCTAssertEqual(model.openRouterUsage, expected)
        XCTAssertNil(model.openRouterUsageError)
        XCTAssertFalse(model.isRefreshingOpenRouterUsage)
    }

    func testRemoteErrorDoesNotDiscardLocalAnalytics() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "Usage temporarily unavailable" }
        }
        let (store, _) = makeStore()
        store.save(.fixture())
        let model = AnalyticsPageModel(store: store) { throw TestError() }

        await model.refreshOpenRouterUsage()

        XCTAssertEqual(model.summary.callCount, 1)
        XCTAssertNil(model.openRouterUsage)
        XCTAssertEqual(model.openRouterUsageError, "Usage temporarily unavailable")
    }

    private func makeStore() -> (TranscriptionAnalyticsStore, UserDefaults) {
        let suite = "AnalyticsPageModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (
            TranscriptionAnalyticsStore(
                userDefaults: defaults,
                key: "analytics",
                notificationCenter: NotificationCenter()
            ),
            defaults
        )
    }
}

private extension TranscriptionMetric {
    static func fixture(
        provider: String = "OpenRouter",
        model: String = "qwen/qwen3-asr-0.6b"
    ) -> Self {
        .init(
            provider: provider,
            model: model,
            latencyMilliseconds: 100,
            outcome: .success
        )
    }
}
