# OpenRouter Qwen3 ASR Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenRouter cloud transcription with selectable Qwen3 ASR 0.6B and 1.7B models and AirType attribution headers.

**Architecture:** Add OpenRouter as a first-class `TranscriptionProvider` with independently persisted credentials and model choice. A focused service owns OpenRouter's JSON/base64 STT wire contract, while the existing settings views and application dispatcher select and call it.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation `URLSession`, XCTest, Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-08-27-openrouter-qwen3-asr.md`

## Global Constraints

- Support only `qwen/qwen3-asr-0.6b` and `qwen/qwen3-asr-1.7b`.
- Send `HTTP-Referer: https://www.airtype.space` and `X-OpenRouter-Title: AirType` on every OpenRouter transcription request.
- Preserve all existing transcription providers and unrelated untracked files.

---

### Task 1: OpenRouter settings contract

**Files:**
- Modify: `Sources/Models/Settings.swift`
- Test: `Tests/AirtypeTests/TranscriptionRequestTests.swift`

**Interfaces:**
- Consumes: `UserDefaults`, `TranscriptionProvider`
- Produces: `.openrouter`, `Settings.openrouterTranscriptionApiKey`, `Settings.openrouterTranscriptionModel`, and `Settings.openrouterTranscriptionModels`

- [ ] **Step 1: Write the failing settings test**

Add an XCTest that selects `.openrouter`, persists `sk-or-test` and `qwen/qwen3-asr-1.7b`, reloads `Settings`, and asserts the provider, key, model, model catalog, key URL, and configuration state.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter TranscriptionRequestTests/testOpenRouterSettingsPersistSupportedModelAndCredentials`

Expected: compilation fails because `.openrouter` and its settings do not exist.

- [ ] **Step 3: Implement the minimal settings support**

Add the provider case, `https://openrouter.ai/keys`, API-key and model defaults keys/properties, the two literal model slugs, computed-property branches, validation, and initialization with `qwen/qwen3-asr-0.6b` as the default.

- [ ] **Step 4: Run the settings test to verify it passes**

Run: `swift test --filter TranscriptionRequestTests/testOpenRouterSettingsPersistSupportedModelAndCredentials`

Expected: PASS.

### Task 2: OpenRouter STT request and response

**Files:**
- Create: `Sources/Services/OpenRouterTranscriptionService.swift`
- Modify: `Tests/AirtypeTests/TranscriptionRequestTests.swift`

**Interfaces:**
- Consumes: `Settings.openrouterTranscriptionApiKey`, `Settings.openrouterTranscriptionModel`, audio file URL, injected `URLSession`
- Produces: `OpenRouterTranscriptionService.transcribe(audioURL:) async throws -> String`

- [ ] **Step 1: Write the failing wire-contract test**

Use the existing capture `URLProtocol` to call the real service. Assert the URL and POST method, bearer token, `application/json`, exact AirType attribution headers, selected model, base64 audio, inferred format, and returned `text`.

- [ ] **Step 2: Run the wire-contract test to verify it fails**

Run: `swift test --filter TranscriptionRequestTests/testOpenRouterRequestUsesQwenModelJSONAudioAndAirTypeAttribution`

Expected: compilation fails because `OpenRouterTranscriptionService` does not exist.

- [ ] **Step 3: Implement the minimal service**

Build a Codable request with `model` and `input_audio`, send it to `https://openrouter.ai/api/v1/audio/transcriptions`, decode `{ "text": ... }`, and map missing key, invalid response, HTTP/API error, and empty text into `LocalizedError` cases.

- [ ] **Step 4: Run request tests to verify they pass**

Run: `swift test --filter TranscriptionRequestTests`

Expected: PASS.

### Task 3: Provider UI and application dispatch

**Files:**
- Modify: `Sources/Views/AirtypeSettingsView.swift`
- Modify: `Sources/Views/SetupWizardView.swift`
- Modify: `Sources/AirtypeApp.swift`

**Interfaces:**
- Consumes: `.openrouter`, `$settings.openrouterTranscriptionApiKey`, `$settings.openrouterTranscriptionModel`, `OpenRouterTranscriptionService`
- Produces: selectable OpenRouter settings in both setup surfaces and an active non-streaming transcription path

- [ ] **Step 1: Extend the existing integration test to require OpenRouter dispatchable behavior**

Add OpenRouter to the cloud entry-point request test and assert the captured request returns `recognized` while using the selected model.

- [ ] **Step 2: Run the integration test to verify it fails**

Run: `swift test --filter TranscriptionRequestTests/testCloudEntryPointsForwardVocabularyToOutgoingRequests`

Expected: FAIL until the service and settings are wired into the supported cloud paths.

- [ ] **Step 3: Implement UI and dispatcher wiring**

Add an OpenRouter settings card matching the ElevenLabs picker/key layout, add setup wizard bindings and picker behavior, create the service with app settings, and dispatch `.openrouter` recordings to it.

- [ ] **Step 4: Run focused tests and compile the app**

Run: `swift test --filter TranscriptionRequestTests`

Expected: PASS and the Airtype target compiles.

### Task 4: Documentation and regression verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: implemented provider and supported model catalog
- Produces: user-facing documentation for OpenRouter cloud transcription

- [ ] **Step 1: Update cloud-provider documentation**

List OpenRouter among cloud transcription providers and document the two supported Qwen3 ASR models plus OpenRouter's dedicated STT endpoint.

- [ ] **Step 2: Run focused and full verification**

Run: `swift test --filter TranscriptionRequestTests` and `swift test`.

Expected: focused tests pass; full-suite result is recorded, including any reproduction of the pre-existing CoreData/XPC baseline crash.

- [ ] **Step 3: Review and commit**

Inspect `git diff --check`, `git diff`, and `git status`, then commit only the feature files with message `feat: add OpenRouter Qwen3 ASR transcription`.
