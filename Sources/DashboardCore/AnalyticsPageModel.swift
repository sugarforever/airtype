import Foundation
import Observation

public struct OpenRouterKeyUsageSnapshot: Equatable, Sendable {
    public let total: Double
    public let daily: Double
    public let weekly: Double
    public let monthly: Double
    public let limit: Double?
    public let limitRemaining: Double?
    public let limitReset: String?

    public init(
        total: Double,
        daily: Double,
        weekly: Double,
        monthly: Double,
        limit: Double?,
        limitRemaining: Double?,
        limitReset: String?
    ) {
        self.total = total
        self.daily = daily
        self.weekly = weekly
        self.monthly = monthly
        self.limit = limit
        self.limitRemaining = limitRemaining
        self.limitReset = limitReset
    }
}

@MainActor
@Observable
@available(macOS 14.0, *)
public final class AnalyticsPageModel {
    public typealias LoadOpenRouterUsage = @MainActor () async throws -> OpenRouterKeyUsageSnapshot

    public private(set) var summary: AnalyticsSummary
    public private(set) var recentRecords: [TranscriptionMetric]
    public private(set) var openRouterUsage: OpenRouterKeyUsageSnapshot?
    public private(set) var openRouterUsageError: String?
    public private(set) var isRefreshingOpenRouterUsage = false
    public private(set) var isClearConfirmationPresented = false

    @ObservationIgnored private let store: TranscriptionAnalyticsStore
    @ObservationIgnored private let loadOpenRouterUsage: LoadOpenRouterUsage?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var notificationToken: NSObjectProtocol?

    public init(
        store: TranscriptionAnalyticsStore = .shared,
        loadOpenRouterUsage: LoadOpenRouterUsage? = nil
    ) {
        self.store = store
        self.loadOpenRouterUsage = loadOpenRouterUsage
        self.notificationCenter = store.notificationCenter
        let records = store.records
        self.summary = AnalyticsSummary(records: records)
        self.recentRecords = Array(records.prefix(50))
        self.notificationToken = store.notificationCenter.addObserver(
            forName: .transcriptionAnalyticsDidChange,
            object: store,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadLocal()
            }
        }
    }

    deinit {
        if let notificationToken {
            notificationCenter.removeObserver(notificationToken)
        }
    }

    public func reloadLocal() {
        let records = store.records
        let newSummary = AnalyticsSummary(records: records)
        let newRecent = Array(records.prefix(50))
        if summary != newSummary { summary = newSummary }
        if recentRecords != newRecent { recentRecords = newRecent }
    }

    public func refreshOpenRouterUsage() async {
        guard let loadOpenRouterUsage else { return }
        isRefreshingOpenRouterUsage = true
        defer { isRefreshingOpenRouterUsage = false }
        do {
            let usage = try await loadOpenRouterUsage()
            if openRouterUsage != usage { openRouterUsage = usage }
            openRouterUsageError = nil
        } catch {
            openRouterUsage = nil
            openRouterUsageError = error.localizedDescription
        }
    }

    public func requestClear() {
        isClearConfirmationPresented = true
    }

    public func cancelClear() {
        isClearConfirmationPresented = false
    }

    public func confirmClear() {
        guard isClearConfirmationPresented else { return }
        store.clear()
        reloadLocal()
        isClearConfirmationPresented = false
    }
}
