# Pause Media During Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pause other applications' active media playback while Airtype records, then resume playback when recording ends.

**Architecture:** Add a small recording-audio interruption controller in `Sources/Services` with an injected media playback boundary. The macOS implementation dynamically queries the bounded system Now Playing state and process identity, sends explicit pause/play commands only when playback is active, and resumes only if the same process still owns Now Playing. `AppState` owns the controller so regular and streaming recording share one lifecycle. If the system symbols are unavailable or the query times out, the feature safely does nothing.

**Tech Stack:** Swift 5.9, AppKit, MediaRemote (dynamically loaded), XCTest, macOS 14+

**Spec:** User request in the Codex task dated 2026-09-01.

## Global Constraints

- Preserve existing user-owned and untracked files.
- Keep AppKit and audio-system integration in `Sources/Services`.
- Include new production files in both SwiftPM and the Xcode app target.
- Resume playback only when Airtype paused playback at recording start.

---

### Task 1: Recording media interruption lifecycle

**Files:**
- Create: `Sources/Services/RecordingAudioInterruptionController.swift`
- Create: `Tests/AirtypeTests/RecordingAudioInterruptionControllerTests.swift`
- Modify: `Sources/AirtypeApp.swift`
- Modify: `Airtype.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: macOS Now Playing playback state and explicit system pause/play commands.
- Produces: `RecordingAudioInterruptionController.recordingDidStart()` and `recordingDidEnd()`.

- [x] **Step 1: Write the failing lifecycle tests**

  Cover active playback, no playback, duplicate starts, recording end, and a Now Playing owner change using a stateful fake playback boundary.

- [x] **Step 2: Run the focused test and verify RED**

  Run `swift test --filter RecordingAudioInterruptionControllerTests` and confirm the missing controller causes the expected failure.

- [x] **Step 3: Implement the minimal controller and macOS playback boundary**

  Dynamically load MediaRemote, query the current Now Playing playback state and owner with a bounded timeout, and send explicit pause/play commands only when required by the controller state. Never send a toggle command for unknown, paused, or stopped states because that can launch Music unexpectedly. Resume only when the original process still owns Now Playing.

- [x] **Step 4: Integrate the shared lifecycle into `AppState`**

  Call `recordingDidStart()` immediately before either capture path starts. Call `recordingDidEnd()` on start failure, normal stop, and cancellation; keep calls idempotent for early-return paths.

- [x] **Step 5: Verify the focused and wider builds**

  Run the focused test, `swift test`, `swift build -c release`, an Xcode Debug app build, and `git diff --check`.
