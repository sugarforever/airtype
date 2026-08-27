import Foundation

public extension Notification.Name {
    static let transcriptionAnalyticsDidChange = Notification.Name(
        "TranscriptionAnalyticsDidChange"
    )
}

public struct TranscriptionMetric: Codable, Identifiable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case success
        case failure
    }

    public let id: UUID
    public let startedAt: Date
    public let provider: String
    public let model: String
    public let latencyMilliseconds: Double
    public let outcome: Outcome
    public let errorCategory: String?
    public let audioDurationSeconds: Double?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let costUSD: Double?
    public let generationID: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        provider: String,
        model: String,
        latencyMilliseconds: Double,
        outcome: Outcome,
        errorCategory: String? = nil,
        audioDurationSeconds: Double? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil,
        costUSD: Double? = nil,
        generationID: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.provider = provider
        self.model = model
        self.latencyMilliseconds = latencyMilliseconds
        self.outcome = outcome
        self.errorCategory = errorCategory
        self.audioDurationSeconds = audioDurationSeconds
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.generationID = generationID
    }
}

public final class TranscriptionAnalyticsStore: @unchecked Sendable {
    public static let shared = TranscriptionAnalyticsStore()

    private let userDefaults: UserDefaults
    private let key: String
    private let maxEntries: Int
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "transcriptionAnalytics",
        maxEntries: Int = 2_000,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.maxEntries = max(1, maxEntries)
        self.notificationCenter = notificationCenter
    }

    public var records: [TranscriptionMetric] {
        lock.withLock { readRecords() }
    }

    public func save(_ record: TranscriptionMetric) {
        lock.withLock {
            var list = readRecords()
            list.insert(record, at: 0)
            if list.count > maxEntries {
                list = Array(list.prefix(maxEntries))
            }
            if let data = try? JSONEncoder().encode(list) {
                userDefaults.set(data, forKey: key)
            }
        }
        notificationCenter.post(name: .transcriptionAnalyticsDidChange, object: self)
    }

    public func clear() {
        lock.withLock {
            userDefaults.removeObject(forKey: key)
        }
        notificationCenter.post(name: .transcriptionAnalyticsDidChange, object: self)
    }

    private func readRecords() -> [TranscriptionMetric] {
        guard let data = userDefaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TranscriptionMetric].self, from: data) else {
            return []
        }
        return decoded
    }
}

public struct ModelAnalyticsSummary: Identifiable, Equatable, Sendable {
    public var id: String { displayName }
    public let provider: String
    public let model: String
    public let callCount: Int
    public let successRate: Double
    public let averageLatencyMilliseconds: Double
    public let totalTokens: Int?
    public let costUSD: Double?

    public var displayName: String { "\(provider) · \(model)" }
}

public struct AnalyticsSummary: Equatable, Sendable {
    public let callCount: Int
    public let successCount: Int
    public let successRate: Double
    public let averageLatencyMilliseconds: Double
    public let p95LatencyMilliseconds: Double
    public let audioDurationSeconds: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let costUSD: Double
    public let hasTokenData: Bool
    public let hasCostData: Bool
    public let modelSummaries: [ModelAnalyticsSummary]

    public init(records: [TranscriptionMetric]) {
        callCount = records.count
        successCount = records.count { $0.outcome == .success }
        successRate = records.isEmpty ? 0 : Double(successCount) / Double(records.count)

        let latencies = records.map(\.latencyMilliseconds)
        averageLatencyMilliseconds = latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count)
        p95LatencyMilliseconds = Self.percentile95(latencies)
        audioDurationSeconds = records.compactMap(\.audioDurationSeconds).reduce(0, +)

        let inputs = records.compactMap(\.inputTokens)
        let outputs = records.compactMap(\.outputTokens)
        let totals = records.compactMap(\.totalTokens)
        let costs = records.compactMap(\.costUSD)
        inputTokens = inputs.reduce(0, +)
        outputTokens = outputs.reduce(0, +)
        totalTokens = totals.reduce(0, +)
        costUSD = costs.reduce(0, +)
        hasTokenData = !inputs.isEmpty || !outputs.isEmpty || !totals.isEmpty
        hasCostData = !costs.isEmpty

        modelSummaries = Dictionary(grouping: records) { record in
            "\(record.provider)\u{0}\(record.model)"
        }.values.map { group in
            let successes = group.count { $0.outcome == .success }
            let modelLatencies = group.map(\.latencyMilliseconds)
            let modelTokens = group.compactMap(\.totalTokens)
            let modelCosts = group.compactMap(\.costUSD)
            return ModelAnalyticsSummary(
                provider: group[0].provider,
                model: group[0].model,
                callCount: group.count,
                successRate: Double(successes) / Double(group.count),
                averageLatencyMilliseconds: modelLatencies.reduce(0, +) / Double(modelLatencies.count),
                totalTokens: modelTokens.isEmpty ? nil : modelTokens.reduce(0, +),
                costUSD: modelCosts.isEmpty ? nil : modelCosts.reduce(0, +)
            )
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[rank]
    }
}
