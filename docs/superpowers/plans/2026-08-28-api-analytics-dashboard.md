# API Analytics Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a privacy-preserving local transcription analytics dashboard with OpenRouter token, cost, generation, and key-usage extensions.

**Architecture:** A `TranscriptionAnalyticsStore` in `DashboardCore` persists bounded metric records and derives summaries independently of UI. `AppState` measures the common provider call and writes success or failure records, while `OpenRouterTranscriptionService` returns optional usage metadata. A small OpenRouter account service fetches current-key aggregates, and an observable page model presents local and remote data to a dedicated SwiftUI view.

**Tech Stack:** Swift 5.9, Swift concurrency, Observation, SwiftUI, XCTest, UserDefaults-backed Codable storage, URLSession.

**Spec:** `docs/superpowers/specs/2026-08-28-api-analytics-dashboard.md`

## Global Constraints

- macOS deployment target remains 14.0.
- Do not add third-party dependencies.
- Do not store audio, transcripts, prompts, vocabulary, or credentials in analytics.
- Recognition accuracy is out of scope; success rate is the reliability metric.
- Keep the branch local and do not push it.

---

### Task 1: Analytics records, persistence, and aggregation

**Files:**
- Create: `Sources/DashboardCore/TranscriptionAnalytics.swift`
- Create: `Tests/DashboardCoreTests/TranscriptionAnalyticsTests.swift`

**Interfaces:**
- Produces: `TranscriptionMetric`, `TranscriptionAnalyticsStore`, `AnalyticsSummary`, and per-model aggregates consumed by instrumentation and UI.

- [ ] **Step 1: Write failing tests** for bounded persistence, success/failure aggregation, optional token/cost values, average latency, nearest-rank P95 latency, and clearing records.
- [ ] **Step 2: Run** `swift test --filter TranscriptionAnalyticsTests` and verify failures are caused by missing analytics types.
- [ ] **Step 3: Implement minimal Codable records and UserDefaults-backed store**, with no text/audio/key fields and a default 2,000-record bound.
- [ ] **Step 4: Implement pure aggregation** with literal expectations: two successes plus one failure yield 66.7% success; `[100, 200, 900]` milliseconds yields P95 `900`; optional values aggregate only when present.
- [ ] **Step 5: Run** `swift test --filter TranscriptionAnalyticsTests` and commit the store and tests.

### Task 2: Decode and return OpenRouter usage metadata

**Files:**
- Modify: `Sources/Services/OpenRouterTranscriptionService.swift`
- Modify: `Tests/AirtypeTests/TranscriptionRequestTests.swift`

**Interfaces:**
- Produces: `OpenRouterTranscriptionResult { text, usage, generationID }` and `transcribeWithMetadata(audioURL:)`; preserves `transcribe(audioURL:) -> String` for existing callers/tests.

- [ ] **Step 1: Add a failing request test** whose complete response includes `usage.seconds`, `input_tokens`, `output_tokens`, `total_tokens`, and `cost`, plus an `X-Generation-Id` header; assert every decoded literal.
- [ ] **Step 2: Run** the focused OpenRouter request test and verify it fails because metadata is not exposed.
- [ ] **Step 3: Implement optional usage decoding and header capture**, keeping missing usage compatible and preserving existing error behavior.
- [ ] **Step 4: Run** `swift test --filter TranscriptionRequestTests` and commit.

### Task 3: Instrument the common transcription path

**Files:**
- Modify: `Sources/AirtypeApp.swift`
- Create: `Tests/AirtypeTests/TranscriptionAnalyticsInstrumentationTests.swift`

**Interfaces:**
- Consumes: `TranscriptionAnalyticsStore` and `OpenRouterTranscriptionResult`.
- Produces: a small testable `TranscriptionAttempt` helper that builds exactly one success or failure metric per provider attempt.

- [ ] **Step 1: Write failing tests** proving success preserves provider/model/latency/OpenRouter usage, failure stores a sanitized error category, and completion is idempotent.
- [ ] **Step 2: Run** the focused instrumentation tests and verify missing-type failures.
- [ ] **Step 3: Implement the attempt helper**, measuring with `ContinuousClock` and accepting an injected completion sink.
- [ ] **Step 4: Wrap the non-streaming provider switch** so every supported provider records success/failure and OpenRouter supplies optional usage; derive audio duration without persisting audio content.
- [ ] **Step 5: Run** focused instrumentation and transcription tests and commit.

### Task 4: Current OpenRouter key usage

**Files:**
- Create: `Sources/Services/OpenRouterKeyUsageService.swift`
- Create: `Tests/AirtypeTests/OpenRouterKeyUsageServiceTests.swift`

**Interfaces:**
- Produces: `OpenRouterKeyUsage` and `fetch()` using the existing inference key against `GET /api/v1/key`.

- [ ] **Step 1: Write failing URLProtocol-backed tests** for request method/authentication, full documented usage decoding, missing key, unauthorized response, and malformed response.
- [ ] **Step 2: Run** `swift test --filter OpenRouterKeyUsageServiceTests` and verify missing-type failures.
- [ ] **Step 3: Implement the service** without logging credentials and with user-friendly errors.
- [ ] **Step 4: Run** the focused service tests and commit.

### Task 5: Analytics page model and SwiftUI dashboard

**Files:**
- Create: `Sources/DashboardCore/AnalyticsPageModel.swift`
- Create: `Sources/Views/AnalyticsView.swift`
- Modify: `Sources/DashboardCore/DashboardModel.swift`
- Modify: `Sources/Views/DashboardSidebar.swift`
- Modify: `Sources/Views/MainView.swift`
- Modify: `Sources/Services/MainWindowController.swift`
- Create: `Tests/DashboardCoreTests/AnalyticsPageModelTests.swift`
- Modify: `Tests/DashboardCoreTests/DashboardSidebarTests.swift`

**Interfaces:**
- Consumes: local store summaries and an injected asynchronous key-usage loader.
- Produces: `.analytics` navigation and a page with overview cards, model comparison, recent requests, clear action, refresh state, and OpenRouter quota section.

- [ ] **Step 1: Write failing model tests** for initial local summary, notification-driven refresh, clear behavior, successful remote usage, and remote errors without losing local data.
- [ ] **Step 2: Add a failing sidebar test** asserting Analytics navigation title and symbol through destination behavior.
- [ ] **Step 3: Run** focused DashboardCore tests and verify expected failures.
- [ ] **Step 4: Implement the observable page model** with injected local store and key-usage loader.
- [ ] **Step 5: Implement `AnalyticsView`** using small native SwiftUI subviews, stable IDs, semantic formatting, empty states, and unavailable markers for provider-specific fields.
- [ ] **Step 6: Wire destination, sidebar, window controller, and refresh lifecycle**, then run focused tests and commit.

### Task 6: Verification and development launch

**Files:**
- Modify only files required by issues found during verification.

**Interfaces:**
- Consumes all prior tasks; produces the signed local development app.

- [ ] **Step 1: Run** `swift test --filter TranscriptionAnalyticsTests`, `swift test --filter TranscriptionRequestTests`, `swift test --filter OpenRouterKeyUsageServiceTests`, and focused dashboard tests.
- [ ] **Step 2: Run** `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug -derivedDataPath .build/xcode-signed-debug build` and verify `BUILD SUCCEEDED`.
- [ ] **Step 3: Review the final diff** for credential/text/audio leakage, unrelated files, and migration risks.
- [ ] **Step 4: Request code review**, address findings with failing tests first, and rerun verification.
- [ ] **Step 5: Launch** with `./scripts/run-debug-app.sh`, confirm the fixed signed app path, and commit any final corrections.

