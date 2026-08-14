# Dashboard, History, and Vocabulary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Airtype's compact settings-only window with a minimal four-destination dashboard that exposes full-text history, learned corrections, and a local proper-noun vocabulary used by Enhancement.

**Architecture:** Add isolated `VocabularyCore` and `DashboardCore` Swift package targets, back vocabulary with a new table in the existing SQLite database, extend correction learning with explicit browse/delete APIs, and place both behind main-actor dashboard models. Split the SwiftUI window into a sidebar container plus focused Home, History, Vocabulary, and Settings views; keep all expensive work off view rendering and the transcription/insertion path.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Observation, Foundation, SQLite3, XCTest, macOS 14+

## Global Constraints

- Keep transcription, Accessibility insertion, and edit observation free of vocabulary and UI work.
- Keep transcription history, learned corrections, and proper nouns local to the Mac.
- Retain exactly the latest 50 transcription-history entries.
- Proper-noun Enhancement selection is newest-first with a strict 300 estimated-token budget.
- Learned-correction retrieval retains its existing five-example, 300-token, 5 ms limits.
- Use Airtype's existing system colors and `Theme.brand`; introduce no separate color palette.
- History text is always complete and has no line limit.
- Use `square.on.square` for copy and a temporary brand-green `checkmark` for success.
- Proper nouns are global; aliases, fuzzy ranking, per-app scope, language scope, and usage statistics are out of scope.
- Preserve unrelated user files and untracked work.

---

### Task 1: VocabularyCore model, normalization, and token-budget selection

**Files:**
- Modify: `Package.swift`
- Create: `Sources/VocabularyCore/VocabularyTerm.swift`
- Create: `Sources/VocabularyCore/VocabularyRepository.swift`
- Test: `Tests/VocabularyCoreTests/VocabularyRepositoryTests.swift`

**Interfaces:**
- Consumes: Foundation `Date`, `UUID`, and UTF-8 strings.
- Produces: `VocabularyTerm`, `VocabularyRepository`, `VocabularyRepositoryError`, and the async actor methods `allTerms()`, `add(_:now:)`, `delete(id:)`, and `promptTerms(tokenBudget:)`.

- [ ] **Step 1: Add the separate package target and write failing repository tests**

Add `VocabularyCore` as a library product and target, add a `VocabularyCoreTests` test target at `Tests/VocabularyCoreTests`, make the executable depend on both core libraries, and exclude `VocabularyCore` from the executable source path alongside `CorrectionLearning`. Test normalization, duplicate rejection, newest-first selection, and strict budget enforcement:

```swift
import XCTest
@testable import VocabularyCore

final class VocabularyRepositoryTests: XCTestCase {
    func testAddTrimsAndRejectsNormalizedDuplicate() async throws {
        let store = MemoryVocabularyStore()
        let repository = VocabularyRepository(store: store)
        let first = try await repository.add("  Cloudflare  ", now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(first.value, "Cloudflare")
        do {
            _ = try await repository.add("cloudflare", now: .now)
            XCTFail("Expected duplicateTerm")
        } catch VocabularyRepositoryError.duplicateTerm {
            // Expected.
        }
    }

    func testPromptTermsAreNewestFirstAndNeverExceedBudget() async throws {
        let repository = VocabularyRepository(store: MemoryVocabularyStore())
        _ = try await repository.add("OldTerm", now: Date(timeIntervalSince1970: 1))
        _ = try await repository.add("NewestTerm", now: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(await repository.promptTerms(tokenBudget: 3), ["NewestTerm"])
    }
}
```

- [ ] **Step 2: Run the focused tests and verify the red state**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter VocabularyRepositoryTests`

Expected: FAIL because `VocabularyCore`, `VocabularyRepository`, and `MemoryVocabularyStore` do not exist.

- [ ] **Step 3: Implement the model and repository contract**

Define the public model and persistence protocol in `VocabularyTerm.swift`:

```swift
public struct VocabularyTerm: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let value: String
    public let normalizedValue: String
    public let createdAt: Date
}

public protocol VocabularyStoring: Sendable {
    func loadTerms() throws -> [VocabularyTerm]
    func insert(_ term: VocabularyTerm) throws
    func delete(id: UUID) throws
}
```

Implement `VocabularyRepository` as an actor. Normalize with canonical composition, lowercase, and collapsed whitespace. Estimate each term as `max(1, (term.value.utf8.count + 3) / 4)`. `promptTerms(tokenBudget:)` sorts by `createdAt` descending with UUID as a stable tie-breaker and stops before the first term that would exceed the remaining budget; it never emits a partial term.

Provide `MemoryVocabularyStore` in the test file as a locked in-memory protocol implementation.

- [ ] **Step 4: Run repository tests**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter VocabularyRepositoryTests`

Expected: PASS.

- [ ] **Step 5: Commit the independent core contract**

```bash
git add Package.swift Sources/VocabularyCore Tests/VocabularyCoreTests/VocabularyRepositoryTests.swift
git commit -m "feat: add vocabulary core repository"
```

---

### Task 2: SQLite vocabulary persistence in the existing local database

**Files:**
- Create: `Sources/VocabularyCore/SQLiteVocabularyStore.swift`
- Test: `Tests/VocabularyCoreTests/SQLiteVocabularyStoreTests.swift`
- Modify: `Airtype.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `VocabularyStoring` and the existing database URL `~/Library/Application Support/Airtype/corrections.sqlite3`.
- Produces: `SQLiteVocabularyStore.init(url:)` and persistent `vocabulary_terms` rows.

- [ ] **Step 1: Write failing SQLite round-trip and uniqueness tests**

```swift
func testRoundTripReturnsNewestFirst() throws {
    let store = try SQLiteVocabularyStore(url: temporaryDatabaseURL())
    try store.insert(VocabularyTerm(id: UUID(), value: "Old", normalizedValue: "old", createdAt: Date(timeIntervalSince1970: 1)))
    try store.insert(VocabularyTerm(id: UUID(), value: "New", normalizedValue: "new", createdAt: Date(timeIntervalSince1970: 2)))
    XCTAssertEqual(try store.loadTerms().map(\.value), ["New", "Old"])
}

func testNormalizedValueIsUnique() throws {
    let store = try SQLiteVocabularyStore(url: temporaryDatabaseURL())
    let first = VocabularyTerm(id: UUID(), value: "Cloudflare", normalizedValue: "cloudflare", createdAt: .now)
    try store.insert(first)
    XCTAssertThrowsError(try store.insert(VocabularyTerm(id: UUID(), value: "CLOUDFLARE", normalizedValue: "cloudflare", createdAt: .now)))
}
```

- [ ] **Step 2: Run the store tests and verify failure**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter SQLiteVocabularyStoreTests`

Expected: FAIL because `SQLiteVocabularyStore` is undefined.

- [ ] **Step 3: Implement WAL-backed prepared statements**

Create the table:

```sql
CREATE TABLE IF NOT EXISTS vocabulary_terms (
    id TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,
    normalized_value TEXT NOT NULL UNIQUE,
    created_at REAL NOT NULL
);
```

Use `SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX`, `PRAGMA journal_mode=WAL`, `PRAGMA synchronous=NORMAL`, a 100 ms busy timeout, prepared insert/delete/select statements, and `ORDER BY created_at DESC, id DESC`. Link `sqlite3` from the `VocabularyCore` target.

- [ ] **Step 4: Add VocabularyCore files to the Xcode app target and run persistence tests**

Update `Airtype.xcodeproj/project.pbxproj` with a `VocabularyCore` group and source-build entries for all three module files.

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter SQLiteVocabularyStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit persistence**

```bash
git add Sources/VocabularyCore/SQLiteVocabularyStore.swift Tests/VocabularyCoreTests/SQLiteVocabularyStoreTests.swift Airtype.xcodeproj/project.pbxproj Package.swift
git commit -m "feat: persist proper nouns locally"
```

---

### Task 3: Browsing and deleting learned corrections

**Files:**
- Modify: `Sources/CorrectionLearning/CorrectionSampleIndex.swift`
- Modify: `Sources/CorrectionLearning/CorrectionLearningService.swift`
- Test: `Tests/AirtypeTests/CorrectionLearningServiceTests.swift`

**Interfaces:**
- Consumes: existing `CorrectionSampleIndex.samples` and `CorrectionStoring.deleteSamples(ids:)`.
- Produces: `CorrectionLearningService.samples() -> [CorrectionSample]` and `deleteSample(id:)`.

- [ ] **Step 1: Write failing browse/delete tests**

```swift
func testDeleteRemovesSampleFromBrowseAndEnhancementRetrieval() async throws {
    let store = InMemoryCorrectionStore()
    let service = CorrectionLearningService(store: store)
    await service.learn(original: "Cloud Flower", final: "Cloudflare", applicationBundleID: "test")
    let id = try XCTUnwrap(await service.samples().first?.id)
    try await service.deleteSample(id: id)
    XCTAssertTrue(await service.samples().isEmpty)
    XCTAssertTrue(await service.examples(for: "Cloud Flower").isEmpty)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter CorrectionLearningServiceTests/testDeleteRemovesSampleFromBrowseAndEnhancementRetrieval`

Expected: FAIL because browse/delete APIs do not exist.

- [ ] **Step 3: Implement index removal and actor APIs**

Add:

```swift
public mutating func remove(id: UUID) -> Bool {
    let oldCount = samples.count
    samples.removeAll { $0.id == id }
    if samples.count != oldCount { rebuildIndexes() }
    return samples.count != oldCount
}
```

Expose samples ordered by `lastCorrectedAt` descending. `deleteSample(id:)` removes the sample from the index before calling the store, so concurrent retrieval stops using it immediately. Preserve the removed value and add `CorrectionSampleIndex.restore(_:)`; if persistence fails, restore the sample, rebuild indexes, and rethrow so the page model can restore its snapshot and show the local error.

- [ ] **Step 4: Run correction-learning tests**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter CorrectionLearningServiceTests`

Expected: PASS.

- [ ] **Step 5: Commit learned-correction management**

```bash
git add Sources/CorrectionLearning/CorrectionSampleIndex.swift Sources/CorrectionLearning/CorrectionLearningService.swift Tests/AirtypeTests/CorrectionLearningServiceTests.swift
git commit -m "feat: manage learned correction samples"
```

---

### Task 4: Enhancement prompt integration for proper nouns

**Files:**
- Create: `Sources/VocabularyCore/VocabularyPromptBuilder.swift`
- Modify: `Sources/CorrectionLearning/EnhancementPromptBuilder.swift`
- Modify: `Sources/Services/EnhancementService.swift`
- Modify: `Sources/AirtypeApp.swift`
- Test: `Tests/VocabularyCoreTests/VocabularyPromptBuilderTests.swift`
- Modify: `Tests/AirtypeTests/EnhancementPromptTests.swift`

**Interfaces:**
- Consumes: `VocabularyRepository.promptTerms(tokenBudget: 300)` and correction examples.
- Produces: a deterministic proper-noun prompt section and optional `vocabularyRepository` injection into `EnhancementService`.

- [ ] **Step 1: Write failing prompt tests**

```swift
func testTermsRenderAsDelimitedLocalVocabulary() {
    let section = VocabularyPromptBuilder().section(terms: ["Cloudflare", "小木头"])
    XCTAssertTrue(section.contains("LOCAL USER VOCABULARY"))
    XCTAssertTrue(section.contains("- Cloudflare"))
    XCTAssertTrue(section.contains("- 小木头"))
}

func testNoTermsAndNoExamplesPreserveExactBasePrompt() {
    XCTAssertEqual(
        EnhancementPromptBuilder().prompt(examples: [], vocabularySection: ""),
        EnhancementPromptBuilder.basePrompt
    )
}
```

- [ ] **Step 2: Run prompt tests and verify failure**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter PromptTests`

Expected: FAIL because the new builder and prompt parameter are missing.

- [ ] **Step 3: Implement deterministic prompt composition**

`VocabularyPromptBuilder.section(terms:)` returns an empty string for no terms and otherwise renders:

```text
LOCAL USER VOCABULARY:
These are correct spellings of terms the user commonly uses. Use them only when they fit the spoken context.
- Cloudflare
- 小木头
```

Change `EnhancementPromptBuilder.prompt` to `prompt(examples:vocabularySection:)`, preserving `basePrompt` byte-for-byte when both inputs are empty. Append vocabulary before contextual learned-correction examples.

Inject an optional `VocabularyRepository` into `EnhancementService`; immediately before request creation call `await repository.promptTerms(tokenBudget: 300)`. Initialize the repository from the same Application Support database URL in `AppState`, with failure degrading to `nil`.

- [ ] **Step 4: Run prompt tests and the full core suite**

Run: `AIRTYPE_CORE_TESTS=1 swift test`

Expected: all tests PASS.

- [ ] **Step 5: Commit Enhancement integration**

```bash
git add Sources/VocabularyCore/VocabularyPromptBuilder.swift Sources/CorrectionLearning/EnhancementPromptBuilder.swift Sources/Services/EnhancementService.swift Sources/AirtypeApp.swift Tests/VocabularyCoreTests/VocabularyPromptBuilderTests.swift Tests/AirtypeTests/EnhancementPromptTests.swift
git commit -m "feat: guide enhancement with local vocabulary"
```

---

### Task 5: Dashboard models and history behavior

**Files:**
- Move: `Sources/Services/TranscriptionHistory.swift` → `Sources/DashboardCore/TranscriptionHistory.swift`
- Create: `Sources/DashboardCore/DashboardModel.swift`
- Create: `Sources/DashboardCore/HistoryPageModel.swift`
- Create: `Sources/DashboardCore/VocabularyPageModel.swift`
- Test: `Tests/DashboardCoreTests/DashboardModelTests.swift`
- Test: `Tests/DashboardCoreTests/HistoryPageModelTests.swift`
- Test: `Tests/DashboardCoreTests/VocabularyPageModelTests.swift`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `TranscriptionHistory`, `VocabularyRepository`, and `CorrectionLearningService`.
- Produces: a separate `DashboardCore` library target containing `DashboardDestination`, `DashboardModel`, and main-actor observable page models with stable snapshots and actions. The target depends on `VocabularyCore` and `CorrectionLearningCore`, not SwiftUI.

- [ ] **Step 1: Write failing model tests**

Cover these exact behaviors:

```swift
func testHistorySearchUsesLocalizedMatchingAndNeverTruncatesText() {
    let longText = String(repeating: "完整历史文字", count: 100)
    let model = HistoryPageModel(entries: [.fixture(text: longText)])
    model.query = "历史"
    XCTAssertEqual(model.filteredEntries.first?.text, longText)
}

func testVocabularyDisplayIsLocalizedSortedButPromptOrderRemainsRepositoryOwned() async throws {
    let model = VocabularyPageModel(repository: repository, learningService: learningService)
    await model.load()
    XCTAssertEqual(model.visibleTerms.map(\.value), model.visibleTerms.map(\.value).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
}
```

Also test navigation defaults to Home, clear-history confirmation state, copied-entry feedback, duplicate inline error, learned-correction filtering, and error-state degradation.

- [ ] **Step 2: Run model tests and verify failure**

Add `DashboardCore` and `DashboardCoreTests` targets to `Package.swift`, then run: `AIRTYPE_CORE_TESTS=1 swift test --filter PageModelTests`

Expected: FAIL because the models do not exist.

- [ ] **Step 3: Make history observable without changing retention**

Move the Foundation-only service into `DashboardCore` and add a `Notification.Name.transcriptionHistoryDidChange`. Post it after `save` and `clear`. Keep `maxEntries = 50` and existing Codable compatibility. Add dependency-injectable UserDefaults suite/key parameters for tests while retaining `.shared` defaults. Add the moved file to the Xcode app target and import `DashboardCore` under `#if SWIFT_PACKAGE` at app call sites.

- [ ] **Step 4: Implement focused main-actor observable models**

Use Observation:

```swift
enum DashboardDestination: String, CaseIterable, Identifiable {
    case home, history, vocabulary, settings
    var id: Self { self }
}

@MainActor @Observable
final class DashboardModel {
    var destination: DashboardDestination = .home
}
```

`HistoryPageModel` owns query, entries, copied ID, and clear-confirmation state. `VocabularyPageModel` owns selected tab, term and correction snapshots, query, validation text, loading state, and local error text. Search uses `localizedStandardContains`; load/add/delete operations use Tasks and only publish changed values.

- [ ] **Step 5: Run all page-model tests**

Run: `AIRTYPE_CORE_TESTS=1 swift test --filter ModelTests`

Expected: PASS.

- [ ] **Step 6: Commit dashboard behavior models**

```bash
git add Package.swift Sources/Services/TranscriptionHistory.swift Sources/DashboardCore Tests/DashboardCoreTests Airtype.xcodeproj/project.pbxproj
git commit -m "feat: add dashboard page models"
```

---

### Task 6: Resizable dashboard shell and Settings extraction

**Files:**
- Modify: `Sources/Views/MainView.swift`
- Create: `Sources/Views/DashboardSidebar.swift`
- Create: `Sources/Views/HomeView.swift`
- Create: `Sources/Views/AirtypeSettingsView.swift`
- Modify: `Sources/Services/MainWindowController.swift`
- Modify: `Airtype.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DashboardModel`, `Settings`, `HotkeyManager`, history snapshots, and existing settings components.
- Produces: the four-destination window shell and unchanged settings behavior under Settings.

- [ ] **Step 1: Extract settings without changing behavior**

Move the existing scrollable settings sections and their helper subviews from `MainView.swift` into `AirtypeSettingsView.swift`. Keep bindings, provider logic, permission checks, and copy unchanged. `MainView` becomes the dashboard container.

- [ ] **Step 2: Implement sidebar and Home**

Use a fixed sidebar near 168 points and a flexible content region. Sidebar rows use `Button`, SF Symbols, system label colors, and the existing `Theme` palette. Home shows ready state, the configured primary shortcut, today's history count, today's learned-correction count, and two complete recent entries without promotional cards.

- [ ] **Step 3: Make the NSWindow resizable**

Change the main window style mask to include `.resizable`, set an initial content size around 900 × 680, and a minimum size around 760 × 560. Remove the fixed `.frame(width: 520, height: 700)` from `MainView`; use minimum dimensions and flexible frames instead.

- [ ] **Step 4: Add new files to Xcode and build**

Run: `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Expected: `** BUILD SUCCEEDED **` with the original Settings behavior reachable from the sidebar.

- [ ] **Step 5: Commit the dashboard shell**

```bash
git add Sources/Views/MainView.swift Sources/Views/DashboardSidebar.swift Sources/Views/HomeView.swift Sources/Views/AirtypeSettingsView.swift Sources/Services/MainWindowController.swift Airtype.xcodeproj/project.pbxproj
git commit -m "feat: add resizable Airtype dashboard"
```

---

### Task 7: Full-text History UI

**Files:**
- Rewrite: `Sources/Views/TranscriptionHistoryView.swift`
- Modify: `Sources/Views/MainView.swift`
- Modify: `Sources/Models/HistoryPageModel.swift`

**Interfaces:**
- Consumes: `HistoryPageModel.filteredEntries`, `copy(_:)`, `requestClear()`, and `confirmClear()`.
- Produces: the integrated full-text history destination.

- [ ] **Step 1: Build the full-text lazy card list**

Use `ScrollView` with `LazyVStack` and stable entry IDs. Render `Text(entry.text)` with no `lineLimit`, enable text selection, and show only relative time in the footer. Use `Image(systemName: copiedID == entry.id ? "checkmark" : "square.on.square")`; apply `Theme.brand` only for successful copy.

- [ ] **Step 2: Add search and matching clear action**

Bind search text to the model. Style Clear with the same brand-green foreground and low-opacity brand background used by current secondary actions. Present a native confirmation dialog before calling `confirmClear()`.

- [ ] **Step 3: Remove the separate history window path**

Route existing menu/history actions to `MainWindowController.show(destination: .history)` and remove `historyWindow` ownership. Reuse the existing main window if it is open.

- [ ] **Step 4: Build and manually verify history behavior**

Run: `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Verify: long text is complete, newest is first, copy icon changes to a green check, search filters, and Clear requires confirmation.

- [ ] **Step 5: Commit History UI**

```bash
git add Sources/Views/TranscriptionHistoryView.swift Sources/Views/MainView.swift Sources/Models/HistoryPageModel.swift Sources/Services/MainWindowController.swift
git commit -m "feat: show complete transcription history"
```

---

### Task 8: Proper-noun tag wall and learned-correction UI

**Files:**
- Create: `Sources/Views/VocabularyView.swift`
- Create: `Sources/Views/ProperNounTagWall.swift`
- Create: `Sources/Views/LearnedCorrectionsView.swift`
- Modify: `Sources/Views/MainView.swift`
- Modify: `Airtype.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `VocabularyPageModel`, proper-noun actions, learned-correction browse/delete APIs, and stable model IDs.
- Produces: the Vocabulary destination with Proper Nouns and Learned Corrections tabs.

- [ ] **Step 1: Implement the Proper Nouns tab**

Use a small regular system font and a wrapping layout based on SwiftUI `Layout`, not a grid with fixed columns. The add action presents a focused field, validates inline, and submits through the model. Each tag exposes a hover-only `xmark` delete button and an accessibility label of `Delete <term>`. Creation time is never rendered.

- [ ] **Step 2: Implement the Learned Corrections tab**

Use a lazy compact list whose constant row structure shows muted/struck recognized text, an arrow, corrected text, correction count, and a menu containing Delete. Clicking the row toggles an optional context block; context preserves `contextBefore`, the corrected term, and `contextAfter`. Do not provide edit controls.

- [ ] **Step 3: Add search, local privacy copy, and empty/error states**

Each tab filters its in-memory snapshot. Add quiet states for no terms, no corrections, no search results, and local database failure. State that all vocabulary data remains on this Mac.

- [ ] **Step 4: Build and manually verify layout behavior**

Run: `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug build CODE_SIGNING_ALLOWED=NO`

Verify: tags wrap at minimum and wide window sizes, hundreds of tags scroll smoothly, hover deletion is discoverable, learned context expands, and light/dark mode use existing global colors.

- [ ] **Step 5: Commit Vocabulary UI**

```bash
git add Sources/Views/VocabularyView.swift Sources/Views/ProperNounTagWall.swift Sources/Views/LearnedCorrectionsView.swift Sources/Views/MainView.swift Airtype.xcodeproj/project.pbxproj
git commit -m "feat: add local vocabulary management UI"
```

---

### Task 9: Final performance, regression, and documentation verification

**Files:**
- Modify: `README.md`
- Modify: `Tests/VocabularyCoreTests/VocabularyRepositoryTests.swift`
- Modify: `Tests/AirtypeTests/CorrectionSampleIndexTests.swift`

**Interfaces:**
- Consumes: the complete dashboard and vocabulary implementation.
- Produces: measured performance evidence, green builds, and user-facing local-data documentation.

- [ ] **Step 1: Add a hundreds-of-terms performance test**

Seed 500 vocabulary terms and assert prompt selection returns within a generous 5 ms release-test budget while never exceeding 300 estimated tokens. Keep the existing 1,000-correction retrieval benchmark intact.

- [ ] **Step 2: Run all core tests in Debug and Release**

Run:

```bash
AIRTYPE_CORE_TESTS=1 swift test
AIRTYPE_CORE_TESTS=1 swift test -c release
```

Expected: all tests PASS; printed vocabulary and correction lookup measurements remain below their 5 ms budgets.

- [ ] **Step 3: Build the complete app in Debug and Release**

Run:

```bash
xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Release build CODE_SIGNING_ALLOWED=NO
```

Expected: both builds end with `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Update README privacy and dashboard documentation**

Document that the main window contains Home, History, Vocabulary, and Settings; history keeps 50 complete local text entries; proper nouns and learned corrections are stored in local SQLite; and only bounded prompt guidance is sent to the configured Enhancement provider.

- [ ] **Step 5: Check the final worktree and commit verification changes**

Run:

```bash
git diff --check
git status --short
```

Confirm only intentional task files and the user's pre-existing untracked files remain.

```bash
git add README.md Tests/VocabularyCoreTests/VocabularyRepositoryTests.swift Tests/AirtypeTests/CorrectionSampleIndexTests.swift
git commit -m "test: verify dashboard vocabulary performance"
```
