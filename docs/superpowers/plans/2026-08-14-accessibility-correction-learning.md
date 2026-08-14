# Accessibility Correction Learning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert confirmed speech directly at the macOS cursor, learn compact local correction mappings from subsequent edits, and retrieve a few relevant examples for future Enhancement calls without slowing voice input.

**Architecture:** Pure correction extraction and retrieval components feed an actor-owned in-memory index backed by system SQLite. A main-actor Accessibility adapter inserts text and observes one active range, while `AppState` starts and finishes tracking without awaiting background learning. `EnhancementService` asynchronously retrieves prompt examples from memory under a five-millisecond budget.

**Tech Stack:** Swift 5.9, Swift Package Manager, XCTest, AppKit/ApplicationServices Accessibility APIs, NaturalLanguage, SQLite3, Swift concurrency.

## Global Constraints

- Support the package's existing macOS 13 deployment floor.
- Add no third-party language-processing, database, or Accessibility dependency.
- Never block starting a recording on correction snapshotting, diffing, or persistence.
- Keep all learned data in local Application Support storage; never log learned text.
- Retrieve from memory only, target less than 3 ms, and stop after 5 ms at 1,000 samples.
- Attach at most five examples and approximately 300 tokens to Enhancement.
- Fall back from AX insertion to the existing pasteboard path; fallback insertion does not learn.
- Preserve the user's unrelated untracked files (`Sources/Services/GLMASRAdapter.swift`, `docs/MLX_LOCAL_ASR_PLAN.md`, and `workers/`).

---

### Task 1: Test Target and Correction Extraction

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CorrectionLearning/CorrectionModels.swift`
- Create: `Sources/CorrectionLearning/CorrectionExtractor.swift`
- Create: `Tests/AirtypeTests/CorrectionExtractorTests.swift`

**Interfaces:**
- Produces: `CorrectionHunk`, `CorrectionExtracting`, and `CorrectionExtractor.extract(original:final:) -> [CorrectionHunk]`.
- `CorrectionHunk` contains `original`, `replacement`, `contextBefore`, and `contextAfter`.

- [ ] **Step 1: Add the XCTest target and write failing extraction tests**

Add `.testTarget(name: "AirtypeTests", dependencies: ["Airtype"], path: "Tests/AirtypeTests")` and tests with hand-derived expectations:

```swift
@testable import Airtype
import XCTest

final class CorrectionExtractorTests: XCTestCase {
    func testExtractsEnglishPhraseReplacementWithSentenceContext() {
        let result = CorrectionExtractor().extract(
            original: "Today we deploy with Cloud Flower.",
            final: "Today we deploy with Cloudflare."
        )
        XCTAssertEqual(result, [
            CorrectionHunk(
                original: "Cloud Flower",
                replacement: "Cloudflare",
                contextBefore: "Today we deploy with",
                contextAfter: "."
            )
        ])
    }

    func testExtractsChineseWordReplacement() {
        let result = CorrectionExtractor().extract(
            original: "我们使用瑞艾克特开发应用。",
            final: "我们使用 React 开发应用。"
        )
        XCTAssertEqual(result.first?.replacement, "React")
        XCTAssertEqual(result.first?.contextAfter, "开发应用。")
    }

    func testRejectsLargeRewrite() {
        XCTAssertTrue(CorrectionExtractor().extract(
            original: "alpha beta gamma delta",
            final: "completely unrelated replacement"
        ).isEmpty)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter CorrectionExtractorTests`

Expected: compilation fails because `CorrectionExtractor` and `CorrectionHunk` do not exist.

- [ ] **Step 3: Implement tokenization, difference coalescing, context, and rewrite rejection**

Implement:

```swift
struct CorrectionHunk: Equatable, Sendable {
    let original: String
    let replacement: String
    let contextBefore: String
    let contextAfter: String
}

protocol CorrectionExtracting: Sendable {
    func extract(original: String, final: String) -> [CorrectionHunk]
}

struct CorrectionExtractor: CorrectionExtracting {
    let rewriteThreshold = 0.5
    let maximumContextCharacters = 400

    func extract(original: String, final: String) -> [CorrectionHunk] {
        // NLTokenizer(.word), CollectionDifference, adjacent change coalescing,
        // NLTokenizer(.sentence) context selection, then the 50% rewrite guard.
    }
}
```

Whitespace and punctuation between tokenizer ranges must be retained when reconstructing hunks. Empty-to-text insertions and text-to-empty deletions are valid hunks unless the entire inserted range was deleted.

- [ ] **Step 4: Expand edge-case tests and verify GREEN**

Add separate tests for punctuation, insertion, deletion, adjacent tokens, identical input, complete deletion, and a long sentence capped at 400 characters. Run `swift test --filter CorrectionExtractorTests` and expect all tests to pass.

- [ ] **Step 5: Commit the extractor**

```bash
git add Package.swift Sources/CorrectionLearning/CorrectionModels.swift Sources/CorrectionLearning/CorrectionExtractor.swift Tests/AirtypeTests/CorrectionExtractorTests.swift
git commit -m "feat: extract contextual text corrections"
```

### Task 2: In-Memory Sample Index and Retrieval

**Files:**
- Create: `Sources/CorrectionLearning/CorrectionSampleIndex.swift`
- Create: `Tests/AirtypeTests/CorrectionSampleIndexTests.swift`

**Interfaces:**
- Consumes: `CorrectionHunk` from Task 1.
- Produces: `CorrectionSample`, `CorrectionPromptExample`, and mutating `CorrectionSampleIndex.record(_:at:)`, `retrieve(for:limit:tokenBudget:deadline:)`, and `evictIfNeeded(maximumCount:)`.

- [ ] **Step 1: Write failing tests for merge, contextual separation, ranking, caps, and eviction**

Use fixed dates and literal expected IDs. Include these observable behaviors:

```swift
func testExactMatchRanksAheadOfContextOnlyCandidate() {
    var index = CorrectionSampleIndex(samples: fixtures)
    let results = index.retrieve(
        for: "Deploy Cloud Flower with Workers",
        limit: 5,
        tokenBudget: 300,
        deadline: .now.advanced(by: .milliseconds(5))
    )
    XCTAssertEqual(results.first?.replacement, "Cloudflare")
}

func testEvictionRemovesOldSingleCorrectionNeverMatchedSample() {
    var index = CorrectionSampleIndex(samples: evictionFixtures)
    index.evictIfNeeded(maximumCount: 2)
    XCTAssertEqual(Set(index.samples.map(\.id)), Set([frequentID, recentID]))
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter CorrectionSampleIndexTests`

Expected: compilation fails because `CorrectionSampleIndex` does not exist.

- [ ] **Step 3: Implement deterministic normalization, indexing, retrieval, and eviction**

Use lowercase, Unicode canonical normalization, and collapsed whitespace for exact keys. Maintain `[String: Set<UUID>]` token postings. Fuzzy comparison is restricted to candidate samples, rejects length deltas above two, skips normalized terms shorter than four characters, and uses bounded Levenshtein distance of at most two.

`retrieve` checks `ContinuousClock.now` between stages, returns at most `limit`, and estimates prompt tokens conservatively as `(string.utf8.count + 3) / 4`. Sorting order is relevance score, correction count, last matched date, then ID for deterministic ties.

- [ ] **Step 4: Verify GREEN and measure the 1,000-sample fixture**

Run: `swift test --filter CorrectionSampleIndexTests`

Add a `measure` test with 1,000 samples that prints measured lookup duration and asserts a CI-safe 50 ms ceiling while preserving the production five-millisecond early exit. Expect all tests to pass.

- [ ] **Step 5: Commit retrieval**

```bash
git add Sources/CorrectionLearning/CorrectionSampleIndex.swift Tests/AirtypeTests/CorrectionSampleIndexTests.swift
git commit -m "feat: index and retrieve correction samples"
```

### Task 3: SQLite Persistence and Learning Actor

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CorrectionLearning/CorrectionStore.swift`
- Create: `Sources/CorrectionLearning/CorrectionLearningService.swift`
- Create: `Tests/AirtypeTests/CorrectionStoreTests.swift`
- Create: `Tests/AirtypeTests/CorrectionLearningServiceTests.swift`

**Interfaces:**
- Consumes: `CorrectionHunk`, `CorrectionSample`, `CorrectionSampleIndex`.
- Produces: `CorrectionStoring`, `SQLiteCorrectionStore`, and actor `CorrectionLearningService` with `learn(original:final:applicationBundleID:)` and `examples(for:)`.

- [ ] **Step 1: Link system SQLite and write failing temporary-database tests**

Add `.linkedLibrary("sqlite3")` to the executable target. Tests create database URLs under `FileManager.default.temporaryDirectory` and verify round-trip persistence, compatible sample upsert, 1,000-row sample eviction, 1,000-row edit-session retention, and that session rows expose only metadata.

```swift
func testRoundTripStoresOnlyCorrectionHunks() throws {
    let store = try SQLiteCorrectionStore(url: databaseURL)
    try store.upsert(sample: sample)
    XCTAssertEqual(try store.loadSamples(), [sample])
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter CorrectionStoreTests`

Expected: compilation fails because `SQLiteCorrectionStore` does not exist.

- [ ] **Step 3: Implement SQLite schema, prepared statements, and transactions**

Create `correction_samples` and `edit_sessions` exactly as specified. Bind all user text through prepared statements. Set `PRAGMA journal_mode=WAL`, `PRAGMA synchronous=NORMAL`, and a short busy timeout. Do not emit SQL or bound text into logs.

The store API is synchronous and confined to the learning actor:

```swift
protocol CorrectionStoring: Sendable {
    func loadSamples() throws -> [CorrectionSample]
    func upsert(sample: CorrectionSample) throws
    func deleteSamples(ids: [UUID]) throws
    func recordSession(_ session: EditSessionMetadata) throws
    func markMatched(ids: [UUID], at date: Date) throws
}
```

- [ ] **Step 4: Write actor tests, verify RED, implement actor, then verify GREEN**

Test that `learn` extracts and persists a mapping, `examples` returns prompt examples and updates match statistics, store failure returns no examples without throwing into voice input, and no full original/final text enters `EditSessionMetadata`.

Initialize the actor by loading samples once. `learn` performs extraction and incremental persistence inside actor isolation. `examples` queries only the in-memory index, respects five examples/300 tokens/five milliseconds, and persists match statistics after returning the selected values.

Run: `swift test --filter 'Correction(Store|LearningService)Tests'`

Expected: all focused tests pass.

- [ ] **Step 5: Commit persistence**

```bash
git add Package.swift Sources/CorrectionLearning/CorrectionStore.swift Sources/CorrectionLearning/CorrectionLearningService.swift Tests/AirtypeTests/CorrectionStoreTests.swift Tests/AirtypeTests/CorrectionLearningServiceTests.swift
git commit -m "feat: persist corrections locally"
```

### Task 4: Enhancement Prompt Integration

**Files:**
- Modify: `Sources/Services/EnhancementService.swift`
- Create: `Tests/AirtypeTests/EnhancementPromptTests.swift`

**Interfaces:**
- Consumes: `CorrectionLearningService.examples(for:)` and `CorrectionPromptExample`.
- Produces: injectable `EnhancementPromptBuilding` / `EnhancementPromptBuilder` and an `EnhancementService` initializer that accepts a learning service.

- [ ] **Step 1: Write failing prompt-builder tests**

Test that zero examples returns the existing system instructions byte-for-byte, one example adds a clearly delimited local-correction section with original/replacement/context, and five-example/token limits are enforced by the learning service rather than duplicated in the prompt builder.

```swift
func testNoExamplesPreservesBasePrompt() {
    XCTAssertEqual(
        EnhancementPromptBuilder().prompt(examples: []),
        EnhancementPromptBuilder.basePrompt
    )
}
```

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter EnhancementPromptTests`

Expected: compilation fails because `EnhancementPromptBuilder` does not exist.

- [ ] **Step 3: Implement prompt building and asynchronous retrieval**

Move the current prompt literal unchanged into `EnhancementPromptBuilder.basePrompt`. Add examples as advisory corrections, explicitly instructing the model to apply them only in matching context. In `enhance(text:)`, await `learningService.examples(for: text)` before constructing `ChatCompletionRequest`; retrieval failure yields the base prompt.

- [ ] **Step 4: Verify GREEN**

Run: `swift test --filter EnhancementPromptTests` and then `swift test`.

Expected: prompt tests and the full suite pass.

- [ ] **Step 5: Commit Enhancement integration**

```bash
git add Sources/Services/EnhancementService.swift Tests/AirtypeTests/EnhancementPromptTests.swift
git commit -m "feat: apply learned corrections to enhancement"
```

### Task 5: Accessibility Insertion and Edit Tracking

**Files:**
- Modify: `Sources/Services/TextInserter.swift`
- Create: `Sources/CorrectionLearning/AccessibilityTextClient.swift`
- Create: `Sources/CorrectionLearning/TextEditTracker.swift`
- Create: `Tests/AirtypeTests/TextInserterTests.swift`
- Create: `Tests/AirtypeTests/TextEditTrackerTests.swift`

**Interfaces:**
- Consumes: `CorrectionLearningService.learn(original:final:applicationBundleID:)`.
- Produces: `TextInsertionResult`, `AccessibilityTextClientProtocol`, system `AccessibilityTextClient`, and `@MainActor TextEditTracker`.

- [ ] **Step 1: Write failing insertion capability-ladder tests**

Use an Accessibility client double and a paste fallback closure. Test direct observable insertion, direct non-observable insertion, immediate paste fallback on unsupported AX insertion, and permission failure. Assert returned behavior, not double call existence:

```swift
func testUnsupportedAXInsertionReturnsSuccessfulUnobservablePasteResult() async throws {
    let result = try await inserter.insert(text: "hello")
    XCTAssertEqual(result, .insertedByPaste)
}
```

- [ ] **Step 2: Run and verify RED, then implement `TextInserter` and AX client**

Run: `swift test --filter TextInserterTests`; expect missing APIs.

The system client obtains the focused application/element, reads `kAXSelectedTextRangeAttribute`, sets `kAXSelectedTextAttribute`, verifies a readable range, and creates/removes `AXObserver` notifications. AX errors denoting unsupported attributes cause fallback; permission failure retains the existing error.

Run the focused test again and expect it to pass.

- [ ] **Step 3: Write failing edit-session lifecycle tests**

Test that focus departure finalizes once, recording start requests non-blocking finalization, invalid ranges discard, complete deletion discards, and a second insertion replaces/finalizes the prior active session safely.

- [ ] **Step 4: Implement tracker and verify GREEN**

`TextEditTracker` owns one `ActiveEditSession` with original text, range anchor, bundle ID, and element token. AX callbacks only mark changes or finish the session. On finish, read a bounded current range, clear the active session immediately, and start an unstructured utility-priority task that calls the learning actor. `finishForRecordingStart()` returns synchronously and never awaits learning.

Run: `swift test --filter '(TextInserter|TextEditTracker)Tests'`.

Expected: all focused tests pass.

- [ ] **Step 5: Commit Accessibility services**

```bash
git add Sources/Services/TextInserter.swift Sources/CorrectionLearning/AccessibilityTextClient.swift Sources/CorrectionLearning/TextEditTracker.swift Tests/AirtypeTests/TextInserterTests.swift Tests/AirtypeTests/TextEditTrackerTests.swift
git commit -m "feat: track corrections after direct insertion"
```

### Task 6: Application Flow, Settings, and Preview Removal

**Files:**
- Modify: `Sources/AirtypeApp.swift`
- Modify: `Sources/Models/Settings.swift`
- Modify: `Sources/Views/MainView.swift`
- Modify: `Sources/Views/FloatingView.swift`
- Create: `Tests/AirtypeTests/CorrectionLearningFlowTests.swift`

**Interfaces:**
- Consumes: observable `TextInsertionResult`, `TextEditTracker`, and shared `CorrectionLearningService`.
- Produces: direct insertion in both streaming and non-streaming flows and user-facing `learnFromCorrections` setting migrated from `previewBeforeInsert` storage.

- [ ] **Step 1: Write failing coordinator tests around an extracted flow helper**

Introduce a small `InsertionCoordinating` boundary or `CorrectionLearningFlow` pure coordinator requested by tests. Verify that learning enabled plus observable insertion starts tracking, learning disabled never tracks, paste insertion never tracks, and recording start asks the tracker to finish without awaiting the learning task.

- [ ] **Step 2: Run and verify RED**

Run: `swift test --filter CorrectionLearningFlowTests`

Expected: compilation fails because the flow coordinator does not exist.

- [ ] **Step 3: Implement coordinator and wire both processing paths**

Create one `CorrectionLearningService`, inject it into `EnhancementService` and `TextEditTracker`, and call tracker finalization at the beginning of `startRecording()`. Replace both `previewBeforeInsert` branches with one direct insertion helper that records history and starts tracking only for observable results.

Migrate the existing defaults key so users who enabled `preview_before_insert` automatically receive `learnFromCorrections = true`; new installs default to false. Rename the published property and use a stable new key after migration.

- [ ] **Step 4: Remove floating Apply/Discard behavior and update settings copy**

Remove preview-driven expansion, editable result state, Apply/Discard actions, and `resignKeyAndActivatePreviousApp` use from `FloatingView`. Keep status/progress content unchanged.

Set the UI copy to:

```text
Learn from my corrections
Insert text immediately and learn subsequent edits locally
```

Add secondary privacy copy stating that relevant examples are sent only to the configured Enhancement provider when Enhancement is enabled.

- [ ] **Step 5: Verify GREEN and commit application integration**

Run `swift test --filter CorrectionLearningFlowTests`, `swift test`, and `swift build`.

Expected: all tests pass and the executable builds successfully.

```bash
git add Sources/AirtypeApp.swift Sources/Models/Settings.swift Sources/Views/MainView.swift Sources/Views/FloatingView.swift Tests/AirtypeTests/CorrectionLearningFlowTests.swift
git commit -m "feat: learn from edits without preview panel"
```

### Task 7: Performance and Final Verification

**Files:**
- Modify: `Tests/AirtypeTests/CorrectionSampleIndexTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes all completed feature interfaces.
- Produces measured retrieval evidence and concise user documentation.

- [ ] **Step 1: Run the 1,000-sample benchmark in release configuration**

Run: `swift test -c release --filter CorrectionSampleIndexTests/testRetrievalPerformanceWithOneThousandSamples`

Record actual duration in the handoff. If it exceeds five milliseconds on the development Mac, profile candidate generation before changing the product budget.

- [ ] **Step 2: Update README behavior and privacy documentation**

Document direct insertion, local correction learning, the lack of cloud synchronization, and that selected relevant examples can accompany requests to the user's configured Enhancement provider.

- [ ] **Step 3: Run full verification**

Run:

```bash
swift test
swift build -c release
git diff --check
git status --short
```

Expected: zero test failures, successful release build, no whitespace errors, and only intentional feature files plus the user's pre-existing untracked files.

- [ ] **Step 4: Commit documentation and benchmark coverage**

```bash
git add README.md Tests/AirtypeTests/CorrectionSampleIndexTests.swift
git commit -m "docs: explain local correction learning"
```
