# Remove Accessibility Edit Tracking Implementation Plan

**Follow-up scope:** The user subsequently requested removal of the Learned Corrections UI as well. Its viewer, deletion controls, homepage metric, and dashboard subscriptions have been removed. The preservation references below describe the original scope; existing local data and Enhancement retrieval remain preserved. Proper-noun management and transcription history are unchanged.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove automatic correction learning that observes edits in external input fields while preserving text insertion, local correction storage/browsing, vocabulary, history, dashboard UI, and Enhancement retrieval.

**Architecture:** Replace the AX observation insertion pipeline with the existing paste insertion path. Remove the tracking-only client, coordinator, tracker, feedback state, setting, diagnostics, project references, and tests; keep the correction extraction/store/index/service because existing local samples remain viewable and usable by Enhancement.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, SwiftPM, Xcode.

**Spec:** User request in the active task: temporarily remove all input-field edit tracking based on Accessibility and retain unrelated changes.

## Global Constraints

- Preserve existing local correction data and the Learned Corrections viewer/delete UI.
- Preserve Accessibility permission used by the existing paste/keyboard-event insertion flow.
- Do not modify unrelated untracked files under `Sources/Services`, `docs`, or `workers`.
- Do not disable App Sandbox as part of this change.

---

### Task 1: Make insertion independent of edit tracking

**Files:**
- Modify: `Sources/Services/TextInserter.swift`
- Modify: `Sources/AirtypeApp.swift`
- Test: `Tests/AirtypeTests/TextInsertionTests.swift`

**Interfaces:**
- Produces: `TextInserter.insert(text:) async throws` using the current pasteboard/Command-V implementation.
- Removes: tracking sessions, AX target capture, correction feedback, and `learningEnabled` insertion arguments.

- [x] **Step 1: Write a failing insertion test proving plain insertion does not create or request an observation session.**
- [x] **Step 2: Run the focused test and confirm it fails against the tracking-aware API.**
- [x] **Step 3: Simplify `TextInserter` and `AppState` to paste-only insertion with history persistence.**
- [x] **Step 4: Run the focused test and confirm it passes.**

### Task 2: Remove tracking-only code and settings

**Files:**
- Delete: `Sources/CorrectionLearning/AccessibilityTextClient.swift`
- Delete: `Sources/CorrectionLearning/TextInsertionCoordinator.swift`
- Delete: `Sources/CorrectionLearning/TextEditTracker.swift`
- Delete: `Tests/AirtypeTests/AccessibilityInsertionTests.swift`
- Modify: `Sources/Models/Settings.swift`
- Modify: `Sources/Views/AirtypeSettingsView.swift`
- Modify: `Sources/Views/FloatingView.swift`
- Modify: `Sources/CorrectionLearning/CorrectionModels.swift`
- Modify: `Airtype.xcodeproj/project.pbxproj`
- Modify: `Package.swift`

**Interfaces:**
- Removes: `learnFromCorrections`, automatic-learning feedback, AX tracking protocols/types, and tracking project references.
- Preserves: `CorrectionHunk`, `CorrectionLearningService`, `CorrectionStore`, `CorrectionSampleIndex`, learned-correction browsing/deletion, and Enhancement examples.

- [x] **Step 1: Remove tracking-only sources, tests, UI, settings, and Xcode references.**
- [x] **Step 2: Search the repository for obsolete tracking symbols and remove remaining references.**
- [x] **Step 3: Build core tests to catch accidental dependencies on deleted tracking types.**

### Task 3: Verify retained behavior and review scope

**Files:**
- Test: `Tests/AirtypeTests/CorrectionLearningServiceTests.swift`
- Test: `Tests/DashboardCoreTests/VocabularyPageModelTests.swift`

**Interfaces:**
- Verifies: persisted corrections remain browsable/deletable and usable as Enhancement examples.

- [x] **Step 1: Run all core tests.**
- [x] **Step 2: Run SwiftPM and Xcode Debug builds.**
- [x] **Step 3: Run `git diff --check`, inspect the final diff, and confirm unrelated files are untouched.**
- [x] **Step 4: Restart the Debug app for manual testing.**
