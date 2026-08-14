import Foundation

public actor CorrectionLearningService {
    private let store: any CorrectionStoring
    private let extractor: any CorrectionExtracting
    private var index: CorrectionSampleIndex
    private var persistenceAvailable: Bool
    private let maximumSampleCount: Int

    public init(
        store: any CorrectionStoring,
        extractor: any CorrectionExtracting = CorrectionExtractor(),
        maximumSampleCount: Int = 1_000
    ) {
        self.store = store
        self.extractor = extractor
        self.maximumSampleCount = maximumSampleCount
        do {
            index = CorrectionSampleIndex(samples: try store.loadSamples())
            persistenceAvailable = true
        } catch {
            index = CorrectionSampleIndex()
            persistenceAvailable = false
        }
    }

    public func learn(
        original: String,
        final: String,
        applicationBundleID: String,
        now: Date = Date()
    ) {
        let hunks = extractor.extract(original: original, final: final)
        let status: EditSessionMetadata.Status = hunks.isEmpty ? .discarded : .learned

        if persistenceAvailable {
            do {
                for hunk in hunks {
                    let sample = index.record(hunk, at: now)
                    try store.upsert(sample: sample)
                }
                let removedIDs = index.evictIfNeeded(maximumCount: maximumSampleCount)
                try store.deleteSamples(ids: removedIDs)
                try store.recordSession(EditSessionMetadata(
                    id: UUID(),
                    applicationBundleID: applicationBundleID,
                    originalCharacterCount: original.count,
                    status: status,
                    createdAt: now,
                    completedAt: now
                ))
            } catch {
                persistenceAvailable = false
            }
        }
    }

    public func examples(
        for text: String,
        now: Date = Date()
    ) -> [CorrectionPromptExample] {
        guard persistenceAvailable else { return [] }
        let examples = index.retrieve(
            for: text,
            limit: 5,
            tokenBudget: 300,
            timeBudget: .milliseconds(5),
            now: now
        )
        guard !examples.isEmpty else { return [] }
        do {
            try store.markMatched(ids: examples.map(\.sampleID), at: now)
        } catch {
            persistenceAvailable = false
        }
        return examples
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
