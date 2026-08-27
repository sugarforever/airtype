# Qwen3-ASR Full Series Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add install, selection, removal, persistence, and transcription support for all ten MLX Community Qwen3-ASR 0.6B and 1.7B precision variants.

**Architecture:** Expand `LocalMLXModel` into the model catalog and derive repository/download metadata from each exact raw value. Preserve existing users through an explicit legacy 1.7B migration, then route every catalog case through the existing Qwen adapter and model manager.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, MLXAudioSTT, Hugging Face Hub

**Spec:** `docs/superpowers/specs/2026-08-27-qwen3-asr-full-series-design.md`

## Global Constraints

- Support 0.6B and 1.7B in 4-bit, 5-bit, 6-bit, 8-bit, and bf16.
- Keep `Qwen3-ASR-0.6B-4bit` as the default model.
- Migrate legacy `Qwen3-ASR-1.7B` settings and installed records to `Qwen3-ASR-1.7B-4bit`.
- Reuse the current MLX Community download, install, removal, and transcription pipeline.
- Do not change inference behavior or claim that a precision variant guarantees better recognition.

---

### Task 1: Model catalog and persistence migration

**Files:**
- Modify: `Tests/AirtypeTests/LocalModelManagerTests.swift`
- Modify: `Sources/Models/Settings.swift`

**Interfaces:**
- Produces: ten `LocalMLXModel` cases with exact `rawValue`, derived `repoID`, and derived `defaultDownloadURL`.
- Produces: initialization migration from the legacy 1.7B raw value in selection and installed-model storage.

- [ ] **Step 1: Write failing catalog and migration tests**

Add table-driven assertions for the ten exact raw values and repositories. Add settings fixtures containing `Qwen3-ASR-1.7B` and assert that initialization selects and records `Qwen3-ASR-1.7B-4bit`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter LocalModelManagerTests`

Expected: compilation failures for the new enum cases and failed migration assertions because the catalog and migration do not exist.

- [ ] **Step 3: Implement the catalog and migration**

Add all ten enum cases, derive `repoID` and the safetensors URL from `rawValue`, and normalize legacy persisted values during `Settings.init`.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter LocalModelManagerTests`

Expected: all focused tests pass.

### Task 2: Route all variants through Qwen transcription

**Files:**
- Modify: `Sources/Services/QwenASRAdapter.swift`
- Modify: `Sources/Services/MLXTranscriptionService.swift`
- Modify: `Tests/AirtypeTests/LocalModelManagerTests.swift`

**Interfaces:**
- Consumes: `LocalMLXModel.repoID` from Task 1.
- Produces: installation and transcription routing that accepts every catalog case without duplicated model switches.

- [ ] **Step 1: Write a failing routing test**

Assert that selecting the final catalog variant installs the exact `mlx-community/Qwen3-ASR-1.7B-bf16` repository and records its raw value.

- [ ] **Step 2: Run the focused test and verify RED**

Run: `swift test --filter LocalModelManagerTests/testInstallsSelectedVariantRepository`

Expected: failure until the final case and generic routing exist.

- [ ] **Step 3: Implement generic Qwen routing**

Have `QwenASRAdapter` use `model.repoID` and have `MLXTranscriptionService` construct the Qwen adapter for any `LocalMLXModel` case.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter LocalModelManagerTests`

Expected: all focused tests pass.

### Task 3: User-facing model documentation

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: the ten model identities from Task 1.
- Produces: a complete supported-model table with approximate repository download sizes.

- [ ] **Step 1: Update the supported-model table**

List all ten exact model identifiers, their approximate download sizes, and concise resource-oriented guidance. Update the vocabulary statement from “both models” to “all Qwen3-ASR models”.

- [ ] **Step 2: Cross-check identifiers**

Compare every README identifier with the literal catalog asserted in `LocalModelManagerTests`; correct any mismatch.

### Task 4: Verification, review, and merge

**Files:**
- Verify all modified files from Tasks 1 through 3.

**Interfaces:**
- Consumes: completed implementation and documentation.
- Produces: reviewed commits merged into local `main`.

- [ ] **Step 1: Run focused verification**

Run: `swift test --filter LocalModelManagerTests`

Expected: zero failures.

- [ ] **Step 2: Run full verification**

Run: `swift test`

Expected: zero feature-related failures; separately record any reproduced baseline-only failure.

- [ ] **Step 3: Review the branch diff**

Request a read-only code review against the branch base. Fix every Critical and Important issue, then rerun focused and full verification.

- [ ] **Step 4: Commit and merge**

Commit the reviewed branch, ensure the primary checkout is clean enough for a non-destructive merge, merge `codex/qwen3-asr-full-series` into local `main`, and verify the merged commit points to the reviewed implementation.
