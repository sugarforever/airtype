import Foundation

public enum CorrectionPersistenceHealth: Equatable, Sendable {
    case available
    case unavailable
}

public struct CorrectionLearningSnapshot: Equatable, Sendable {
    public let samples: [CorrectionSample]
    public let persistenceHealth: CorrectionPersistenceHealth

    public init(
        samples: [CorrectionSample],
        persistenceHealth: CorrectionPersistenceHealth
    ) {
        self.samples = samples
        self.persistenceHealth = persistenceHealth
    }
}

public final class CorrectionLearningService: @unchecked Sendable {
    private let extractor: any CorrectionExtracting
    private let snapshots: CorrectionSnapshotState
    private let persistenceWorker: CorrectionPersistenceWorker

    public init(
        store: any CorrectionStoring,
        extractor: any CorrectionExtracting = CorrectionExtractor(),
        maximumSampleCount: Int = 1_000
    ) {
        self.extractor = extractor

        let initialIndex: CorrectionSampleIndex
        let initialHealth: CorrectionPersistenceHealth
        let requiresReconciliation: Bool
        do {
            initialIndex = CorrectionSampleIndex(
                samples: try withBoundedBusyRetry { try store.loadSamples() }
            )
            initialHealth = .available
            requiresReconciliation = false
        } catch {
            initialIndex = CorrectionSampleIndex()
            initialHealth = .unavailable
            requiresReconciliation = true
        }

        let snapshots = CorrectionSnapshotState(
            index: initialIndex,
            persistenceHealth: initialHealth
        )
        self.snapshots = snapshots
        persistenceWorker = CorrectionPersistenceWorker(
            store: store,
            index: initialIndex,
            persistenceHealth: initialHealth,
            requiresReconciliation: requiresReconciliation,
            maximumSampleCount: maximumSampleCount,
            snapshots: snapshots
        )
    }

    public var persistenceHealth: CorrectionPersistenceHealth {
        get async {
            snapshots.currentSnapshot().persistenceHealth
        }
    }

    public func learn(
        original: String,
        final: String,
        applicationBundleID: String,
        now: Date = Date()
    ) async {
        let hunks = extractor.extract(original: original, final: final)
        await persistenceWorker.learn(
            hunks: hunks,
            originalCharacterCount: original.count,
            applicationBundleID: applicationBundleID,
            now: now
        )
    }

    public func examples(
        for text: String,
        now: Date = Date()
    ) async -> [CorrectionPromptExample] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(5))
        let index = snapshots.currentIndex()
        let examples = index.retrieve(
            for: text,
            limit: 5,
            tokenBudget: 300,
            deadline: deadline,
            clock: clock
        )

        if !examples.isEmpty {
            let ids = examples.map(\.sampleID)
            let persistenceWorker = persistenceWorker
            Task.detached(priority: .utility) {
                await persistenceWorker.recordMatches(ids: ids, at: now)
            }
        }
        return examples
    }

    public func samples() async -> [CorrectionSample] {
        snapshots.currentSnapshot().samples
    }

    public func updates() async -> AsyncStream<CorrectionLearningSnapshot> {
        snapshots.makeStream()
    }

    public func deleteSample(id: UUID) async throws {
        try await persistenceWorker.deleteSample(id: id)
    }

    public static func makeDefault() throws -> CorrectionLearningService {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Airtype", isDirectory: true)
        let store = try SQLiteCorrectionStore(
            url: directory.appendingPathComponent("corrections.sqlite3")
        )
        return CorrectionLearningService(store: store)
    }
}

private final class CorrectionSnapshotState: @unchecked Sendable {
    private let lock = NSLock()
    private var index: CorrectionSampleIndex
    private var snapshot: CorrectionLearningSnapshot
    private var deliveries: [UUID: CorrectionSnapshotDelivery] = [:]

    init(
        index: CorrectionSampleIndex,
        persistenceHealth: CorrectionPersistenceHealth
    ) {
        self.index = index
        snapshot = CorrectionLearningSnapshot(
            samples: Self.sortedSamples(index.samples),
            persistenceHealth: persistenceHealth
        )
    }

    func currentIndex() -> CorrectionSampleIndex {
        lock.withLock { index }
    }

    func currentSnapshot() -> CorrectionLearningSnapshot {
        lock.withLock { snapshot }
    }

    func publish(
        index newIndex: CorrectionSampleIndex,
        persistenceHealth: CorrectionPersistenceHealth
    ) {
        let newSnapshot = CorrectionLearningSnapshot(
            samples: Self.sortedSamples(newIndex.samples),
            persistenceHealth: persistenceHealth
        )
        let currentDeliveries: [CorrectionSnapshotDelivery] = lock.withLock {
            index = newIndex
            guard snapshot != newSnapshot else { return [] }
            snapshot = newSnapshot
            return Array(deliveries.values)
        }
        for delivery in currentDeliveries {
            delivery.enqueue(newSnapshot)
        }
    }

    func makeStream() -> AsyncStream<CorrectionLearningSnapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let id = UUID()
            let delivery = CorrectionSnapshotDelivery(continuation: continuation)
            lock.withLock {
                self.deliveries[id] = delivery
                delivery.enqueue(self.snapshot)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
    }

    private func removeContinuation(id: UUID) {
        _ = lock.withLock {
            deliveries.removeValue(forKey: id)
        }
    }

    private static func sortedSamples(_ samples: [CorrectionSample]) -> [CorrectionSample] {
        samples.sorted {
            if $0.lastCorrectedAt != $1.lastCorrectedAt {
                return $0.lastCorrectedAt > $1.lastCorrectedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

private final class CorrectionSnapshotDelivery: @unchecked Sendable {
    private let continuation: AsyncStream<CorrectionLearningSnapshot>.Continuation
    private let queue = DispatchQueue(label: "com.airtype.correction-learning-snapshot")

    init(continuation: AsyncStream<CorrectionLearningSnapshot>.Continuation) {
        self.continuation = continuation
    }

    func enqueue(_ snapshot: CorrectionLearningSnapshot) {
        queue.async { [continuation] in
            continuation.yield(snapshot)
        }
    }
}

private actor CorrectionPersistenceWorker {
    private let store: any CorrectionStoring
    private let maximumSampleCount: Int
    private let snapshots: CorrectionSnapshotState
    private var index: CorrectionSampleIndex
    private var persistenceHealth: CorrectionPersistenceHealth
    private var requiresReconciliation: Bool

    init(
        store: any CorrectionStoring,
        index: CorrectionSampleIndex,
        persistenceHealth: CorrectionPersistenceHealth,
        requiresReconciliation: Bool,
        maximumSampleCount: Int,
        snapshots: CorrectionSnapshotState
    ) {
        self.store = store
        self.index = index
        self.persistenceHealth = persistenceHealth
        self.requiresReconciliation = requiresReconciliation
        self.maximumSampleCount = maximumSampleCount
        self.snapshots = snapshots
    }

    func learn(
        hunks: [CorrectionHunk],
        originalCharacterCount: Int,
        applicationBundleID: String,
        now: Date
    ) {
        do {
            try reconcileBeforeMutationIfNeeded()
        } catch {
            return
        }

        let previousIndex = index
        var prospectiveIndex = index
        var updatedIDs = Set<UUID>()
        for hunk in hunks {
            updatedIDs.insert(prospectiveIndex.record(hunk, at: now).id)
        }
        let removedIDs = prospectiveIndex.evictIfNeeded(maximumCount: maximumSampleCount)
        let removedIDSet = Set(removedIDs)
        let updatedSamples = prospectiveIndex.samples.filter {
            updatedIDs.contains($0.id) && !removedIDSet.contains($0.id)
        }
        let session = EditSessionMetadata(
            id: UUID(),
            applicationBundleID: applicationBundleID,
            originalCharacterCount: originalCharacterCount,
            status: hunks.isEmpty ? .discarded : .learned,
            createdAt: now,
            completedAt: now
        )

        do {
            try withBoundedBusyRetry {
                try store.applyLearningBatch(
                    upserting: updatedSamples,
                    deleting: removedIDs,
                    session: session
                )
            }
            index = prospectiveIndex
            persistenceHealth = .available
            requiresReconciliation = false
            publish()
        } catch {
            reconcileAfterWriteFailure(fallbackIndex: previousIndex)
        }
    }

    func recordMatches(ids: [UUID], at date: Date) {
        guard !ids.isEmpty else { return }
        do {
            try reconcileBeforeMutationIfNeeded()
            try withBoundedBusyRetry {
                try store.markMatched(ids: ids, at: date)
            }
            index.recordMatches(ids: ids, at: date)
            persistenceHealth = .available
            requiresReconciliation = false
            publish()
        } catch {
            reconcileAfterWriteFailure(fallbackIndex: index)
        }
    }

    func deleteSample(id: UUID) throws {
        try reconcileBeforeMutationIfNeeded()
        guard index.samples.contains(where: { $0.id == id }) else { return }

        let previousIndex = index
        var prospectiveIndex = index
        guard prospectiveIndex.remove(id: id) else { return }
        index = prospectiveIndex
        publish()

        do {
            try withBoundedBusyRetry {
                try store.deleteSamples(ids: [id])
            }
            persistenceHealth = .available
            requiresReconciliation = false
            publish()
        } catch {
            reconcileAfterWriteFailure(fallbackIndex: previousIndex)
            throw error
        }
    }

    private func reconcileBeforeMutationIfNeeded() throws {
        guard requiresReconciliation else { return }
        do {
            index = CorrectionSampleIndex(
                samples: try withBoundedBusyRetry { try store.loadSamples() }
            )
            requiresReconciliation = false
            publish()
        } catch {
            persistenceHealth = .unavailable
            publish()
            throw error
        }
    }

    private func reconcileAfterWriteFailure(fallbackIndex: CorrectionSampleIndex) {
        persistenceHealth = .unavailable
        do {
            index = CorrectionSampleIndex(
                samples: try withBoundedBusyRetry { try store.loadSamples() }
            )
            requiresReconciliation = false
        } catch {
            index = fallbackIndex
            requiresReconciliation = true
        }
        publish()
    }

    private func publish() {
        snapshots.publish(index: index, persistenceHealth: persistenceHealth)
    }
}

private func withBoundedBusyRetry<T>(_ operation: () throws -> T) throws -> T {
    let maximumAttemptCount = 3
    var attempt = 0
    while true {
        do {
            return try operation()
        } catch {
            attempt += 1
            guard attempt < maximumAttemptCount,
                  let storeError = error as? CorrectionStoreError,
                  storeError.isTransientLockContention
            else { throw error }
            Thread.sleep(forTimeInterval: 0.005 * Double(attempt))
        }
    }
}
