# Transcription Vocabulary Implementation Plan

> **For agentic workers:** Execute inline in the user-requested branch; use test-driven-development and requesting-code-review.

**Goal:** Reuse the local Vocabulary for recognition-time guidance in all five transcription backends, independently of Enhancement.

**Architecture:** An immutable, bounded `TranscriptionContext` in VocabularyCore normalizes terms and serializes provider-specific hints. The application loads a fresh snapshot before batch transcription or streaming session initialization, never at transport preconnection. Existing Enhancement behavior stays unchanged.

**Tech Stack:** Swift, SwiftUI, SwiftPM, Xcode, mlx-audio-swift, URLSession.

**Spec:** User-approved conversation: synchronize main, develop on a branch, verify latest MLX context support, implement unified vocabulary support.

## Global Constraints

- Work in `codex/transcription-vocabulary`, no worktree, no push or release.
- Preserve pre-existing untracked GLMASRAdapter.swift, MLX_LOCAL_ASR_PLAN.md, and workers/.
- Use the existing vocabulary database; no new cloud synchronization or learned-correction behavior.
- Explicit opt-in (default off) because cloud requests disclose terms and ElevenLabs keyterms cost extra.
- Omit hints entirely for empty/disabled vocabulary and unsupported model variants.
- Cap counts and UTF-8 payload sizes, skip malformed/oversized terms without blocking later terms, preserve newest-first order.
- Never log vocabulary content. No paid API calls during verification.
- Pin MLXAudio to verified upstream revision `cae704f53bc32a3d0b606823828fbc5bedaaf388` in SwiftPM and Xcode; regenerate lockfiles.

## Task 1: Bounded context and provider serialization

**Files:** Create Sources/VocabularyCore/TranscriptionContext.swift and Tests/VocabularyCoreTests/TranscriptionContextTests.swift; register the source in project.pbxproj.

**Interface:** `TranscriptionContext(terms: [String])`, `.empty`, `load(repository: VocabularyRepository?, enabled: Bool) async`, `multipartData(for: Backend, model: String, boundary: String) -> Data`, `qwenContext: String`, `doubaoContext: String?`.

- [x] Add tests for normalization/deduplication, Unicode, reserved delimiters, count/byte budgets, disabled/nil repository, and fresh snapshots after deletion.
- [x] Add wire-format tests: OpenAI one prompt part, ElevenLabs repeated keyterms parts only for scribe_v2, Mistral repeated context_bias parts, Doubao JSON string containing hotwords, empty no-op.
- [x] Run `AIRTYPE_CORE_TESTS=1 swift test --scratch-path .build/core-tests --filter TranscriptionContextTests`; observe missing-feature failure.
- [x] Implement bounded selection and serialization, then rerun until green.

Representative contract:
```swift
let context = TranscriptionContext(terms: [" Airtype ", "airtype", "小木头"])
XCTAssertEqual(context.qwenContext, "Airtype, 小木头")
XCTAssertEqual(context.multipartData(for: .elevenlabs, model: "scribe_v1", boundary: "test"), Data())
```

## Task 2: Dependency and service integration

**Files:** Package.swift, both Package.resolved files, project.pbxproj; WhisperService.swift, ElevenLabsService.swift, MistralTranscriptionService.swift, LocalASRAdapter.swift, QwenASRAdapter.swift, MLXTranscriptionService.swift, MLXAudioRunner.swift, StreamingTranscriptionProtocol.swift, DoubaoStreamingService.swift.

**Interface:** Add `context: TranscriptionContext = .empty` to public service entry points; keep the same snapshot for every OpenAI chunk. Require the context in internal adapter forwarding. Add `startSession(context:)` to streaming protocol with an empty default on the concrete implementation.

- [x] Expose actual body/config builders internally and add service payload tests before changing their behavior.
- [x] Resolve new pinned MLX revision, retaining model IDs and language behavior.
- [x] Forward context to `model.generate(audio: audio, context: context.qwenContext, language: language)`.
- [x] Append generated multipart fields before file parts; set Doubao `request.corpus.context` to the serialized JSON string only when nonempty.
- [x] Build app with Xcode; run request builder tests without paid network calls.

## Task 3: App opt-in, documentation, verification

**Files:** Settings.swift, AirtypeApp.swift, AirtypeSettingsView.swift, VocabularyView.swift, README.md.

- [x] Persist `transcriptionVocabularyEnabled` with default false, bind the existing Settings object in the voice-input card.
- [x] Load `TranscriptionContext.load(repository: vocabularyRepository, enabled: settings.transcriptionVocabularyEnabled)` immediately before batch dispatch and streaming startSession; do not attach it to preconnect.
- [x] Explain local/cloud privacy, bounded newest-first selection, provider limitations and ElevenLabs surcharge in UI/docs.
- [x] Run complete core suite, service tests and `xcodebuild -project Airtype.xcodeproj -scheme Airtype -configuration Debug -derivedDataPath .build/vocabulary-xcode CODE_SIGNING_ALLOWED=NO build`.
- [x] Request independent code review, fix important findings, rerun verification and `git diff --check`.
- [x] Prepare a scoped local feature commit and handoff; no push or release.

## Sources checked

- MLXAudio PR #126: https://github.com/Blaizzy/mlx-audio-swift/pull/126
- ElevenLabs: https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- Mistral: https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription
- Doubao: https://www.volcengine.com/docs/6561/1354869?lang=en
- OpenAI: https://platform.openai.com/docs/api-reference/audio/createTranscription

Baseline: 81 core tests passed on 2026-08-26. Existing core-only manifest emits an unused HotKey warning.

## Verification record

- Initial request-body tests failed on missing prompt/keyterms/context_bias/corpus, then passed after wiring.
- Independent review found provider filtering after shared limits could starve valid terms. A regression reproduced the failure; per-provider selection fixed it and passed re-review.
- Full `swift test`: 101 tests passed, 0 failures (2026-08-26).
- Xcode Debug app build succeeded with code signing disabled; final incremental build verifies post-review edits.
- Root and Xcode lockfiles agree on mlx-audio `cae704f`, MLX `0.31.4`, MLXLM `3.31.4`.
- Cloud entry-point tests intercept URLSession locally; no paid requests or real audio were sent. Real-provider acceptance and acoustic accuracy have not been benchmarked.
- Existing SwiftUI deprecation and stale SwiftPM module-cache warnings remain outside this feature's scope.
