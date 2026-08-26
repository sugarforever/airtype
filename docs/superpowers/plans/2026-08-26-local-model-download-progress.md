# Local Model Download Progress Implementation Plan

> Execute inline in this task, with test-first implementation and verification before completion.

**Goal:** Show real model download progress in Settings and Setup, followed by a separate loading phase and actionable failures.

**Architecture:** Keep one app-owned `LocalModelManager.shared`. Inject the installer for deterministic tests. Split the runner into `ModelUtils.resolveOrDownloadModel(client:…progressHandler:)` and `Qwen3ASRModel.fromModelDirectory`. Publish value snapshots on the main actor, never the mutable Foundation `Progress` itself.

**Tech Stack:** Swift, SwiftUI, existing pinned MLXAudio and HuggingFace dependencies, XCTest.

**Spec:** User-approved research in this task: real percentage, preparation/loading states, retry, shared task, fixed target model. No speed estimates, cancellation, or resume promises in this increment.

## Constraints

- Work on `codex/local-model-download-progress`; preserve unrelated untracked files.
- Retain macOS 14 minimum and current dependency revisions.
- Retain existing English UI copy conventions and ObservableObject integration.
- Never mark installed until model loading succeeds; do not download real large models in unit tests.

## Task 1: Installation state and download integration

**Files:** `Tests/AirtypeTests/LocalModelManagerTests.swift`, `Sources/Services/LocalModelManager.swift`, `Sources/Services/MLXAudioRunner.swift`, `Package.swift`, `Airtype.xcodeproj/project.pbxproj`.

- [x] Verify baseline with `swift test`.
- [x] Write failing tests for preparation/download/loading transitions, retry clearing stale state, duplicate install prevention, stable model identity, invalid progress, and late callbacks.
- [x] Run `swift test --filter LocalModelManagerTests` and confirm missing-feature failure.
- [x] Add `LocalModelInstallPhase` (`preparing`, `downloading(Double?)`, `loading`), injectable installer, shared manager, guarded progress updates and fixed model capture.
- [x] Replace `fromPretrained` during installation with explicit download then load. Use `Progress.fractionCompleted`, not `completedUnitCount / totalUnitCount`: parent Progress includes weighted children. Preserve token and cache configuration.
- [x] Declare HuggingFace directly in both SwiftPM and Xcode because the runner now constructs its public client and repository types. Keep version 0.9.0.
- [x] Run focused tests and confirm success.

## Task 2: Shared UI

**Files:** `Sources/Views/LocalModelInstallStatusView.swift`, `Sources/Views/AirtypeSettingsView.swift`, `Sources/Views/SetupWizardView.swift`, `Airtype.xcodeproj/project.pbxproj`.

- [x] Observe `LocalModelManager.shared` in both screens.
- [x] Render a labeled linear progress bar for known progress and an indeterminate indicator for preparation, unknown progress, and loading.
- [x] Render model-specific success/error text, and use the existing install action as Retry after failure.
- [x] Disable model selection, duplicate installs and removal while an installation is active; show the active model if selection changes elsewhere.
- [x] Register the shared view in the Xcode project.

## Task 3: Verification

- [x] Run full `swift test` and `git diff --check`.
- [x] Build the app with `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug -derivedDataPath .build/vocabulary-xcode CODE_SIGNING_ALLOWED=NO build`.
- [x] Review state lifetime, accessibility, cache hits, and failure behavior. Record actual verification and limitations here.


## Verification results

- Baseline: `swift test` passed 106 tests.
- Red: new installation tests failed to compile because the phase and injectable installer APIs were absent. The later weighted-progress test failed because the Progress conversion overload was absent.
- Final: `swift test` passed 114 tests, including 8 new installation/progress tests, with zero failures.
- Xcode Debug app build succeeded with signing disabled. Existing dependency resource, deprecated API, module-cache and minimum-version warnings remain; no new warnings in changed source files were observed.
- `git diff --check` passed. Both dependency lockfiles retained their original revisions.
- Independent read-only review found no actionable regressions.
- No real large model download or interactive close/reopen UI validation was performed. Manager behavior was exercised with injected installers; weighted progress used real Foundation Progress parent/child objects.

## Manual follow-up

1. Install an uncached local model in Settings: preparation, moving percentage, loading, installed.
2. Close/reopen Settings during download and confirm progress remains visible; open Setup and confirm the same task is observed.
3. Interrupt network connectivity, verify error and Retry, then restore connectivity and retry.
4. Confirm a cached model reaches loading without requiring a visible download phase.

## Follow-up: Remove appeared to do nothing

User testing found that Remove followed by Install completed immediately. Read-only inspection confirmed both model snapshots and Hub repository caches existed under `~/.cache/huggingface/hub`, while the old removal code targeted the absent `~/Library/Caches/huggingface/hub` path. It also swallowed filesystem errors and always removed the installed record.

- Removal now resolves the same `HubCache.default.cacheDirectory` as installation, including configured Hugging Face cache locations.
- It deletes only the selected repository's Hub cache, metadata and installed snapshot, not the cache root or other models. The UI help notes this repository cache may also be used by other applications.
- Only missing paths are treated as success. Other errors are shown and the installed record is retained. The installed snapshot is removed last so earlier failures leave it usable.
- Four regression tests cover temporary on-disk caches, other-model preservation, repeated removal, real filesystem permission errors, and manager success/failure state.
- Full `swift test`: 118 tests passed, zero failures. Xcode Debug build succeeded. No actual user model files were removed during automated validation.

## Follow-up: Progress stayed near 1% until completion

User testing exposed a gap not covered by the original injected-state tests. A slow loopback HTTP probe on macOS showed that `URLSession.download(for:delegate:)` delivered no `didWriteData` callbacks, although KVO observations of `countOfBytesReceived` changed throughout the transfer. The pinned HuggingFace client's private download delegate depends on that missing callback, so its snapshot sampler repeatedly reports the same fraction until each entire file finishes.

- Added an installation-scoped URLSession delegate that observes real download byte counts and forwards them to the existing per-task download delegate. This retains the library's absolute counters, resume-offset handling and weighted snapshot aggregation.
- The bridge ignores non-download tasks, protects observation storage with a lock, captures the session weakly and releases observations on session invalidation. The runner invalidates its session on success and failure.
- Added a real loopback HTTP integration test with HEAD metadata, a redirect, and a 4 MiB response sent in delayed chunks. It uses the actual pinned `ModelUtils` and `HubClient`, and requires at least three distinct percentages between 5% and 95% while the transfer is unfinished.
- Red: the unmodified URLSession path completed the download but produced **zero** intermediate percentages, failing the test. Green: the bridged session passed the same assertion.
- Full `swift test`: 119 tests passed, zero failures. Xcode Debug app build succeeded. Read-only review found no actionable issues.
- Actual Hugging Face large-file download/UI interaction remains a manual check; the regression test performs real HTTP transfer only on loopback and does not touch user models. HTTP 206 resume and concurrent weight-file transfers remain additional integration coverage opportunities.
