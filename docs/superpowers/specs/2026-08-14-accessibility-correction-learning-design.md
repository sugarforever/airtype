# Accessibility Correction Learning Design

## Objective

Replace AirType's floating-panel confirmation workflow with direct insertion at the focused macOS text cursor. When the user subsequently corrects inserted text, learn compact, contextual before-to-after mappings locally and use only the most relevant mappings as examples during future Enhancement requests.

Voice-input latency is the primary constraint. Insertion, recording, transcription, and Enhancement must never wait for correction extraction or persistence.

## User Experience

The existing **Confirm before inserting** setting becomes **Learn from my corrections**.

When enabled:

1. AirType transcribes and optionally enhances speech as it does today.
2. AirType inserts the result directly into the focused text control without presenting editable text in its floating panel.
3. AirType observes subsequent edits to that inserted range.
4. The edit session ends when focus leaves the target control or the user begins another recording, whichever happens first.
5. AirType extracts useful corrections in the background and stores them locally.

When disabled, AirType inserts text normally and does not create an edit session or read the modified text.

The floating window remains available for recording and processing status. It no longer hosts an Apply/Discard text-editing workflow.

## Native macOS Approach

The implementation uses platform facilities and no third-party storage or language-processing dependency:

- Accessibility APIs (`AXUIElement` and `AXObserver`) for focused-control discovery, selected-text insertion, range capture, and edit/focus notifications.
- Natural Language (`NLTokenizer`) for word and sentence boundaries in English, Chinese, and mixed-language text.
- Swift `CollectionDifference` over tokens for edit extraction.
- The system SQLite library for small, indexed, incremental local persistence.
- Swift concurrency and a dedicated actor for correction indexing and persistence.
- `ContinuousClock` for hot-path timing, with optional `os_signpost` instrumentation in development builds.

SwiftData and Core Data are not used: the sample set is small, and direct SQLite provides lower and more predictable overhead with precise transaction and index control.

## Insertion and Compatibility

Insertion follows a strict capability ladder:

1. Prefer setting `kAXSelectedTextAttribute` on the focused editable element.
2. If direct Accessibility insertion succeeds and the element exposes a reliable text range, begin an observable edit session.
3. If insertion succeeds but reliable reading or observation is unavailable, do not learn from this insertion.
4. If Accessibility insertion is unsupported, immediately fall back to the existing pasteboard and synthetic Command-V path and do not learn.
5. If Accessibility permission is absent, retain the existing permission prompt and error behavior.

Learning failure never turns a successful insertion into an error and never triggers a fallback to the floating editing panel.

## Components and Responsibilities

### `TextInserter`

`TextInserter` gains an Accessibility-backed insertion path and returns an insertion result describing whether the operation is observable. System calls sit behind a small protocol so behavior can be tested without controlling another application.

The observable result contains only what `TextEditTracker` needs: the target element identity, the inserted range, and the inserted text. A pasteboard fallback returns a successful but non-observable result.

### `TextEditTracker`

`TextEditTracker` owns at most one active edit session. It registers Accessibility notifications for focused-element, value, and selected-range changes without polling.

An edit session keeps the original inserted text and target range in memory only. It completes on focus departure or the beginning of the next recording. Starting a new recording does not wait for completion: the tracker snapshots whatever text is immediately available and hands analysis to a background task. If a safe snapshot is not immediately available, the session is discarded.

The tracker abandons learning when the target disappears, the inserted range cannot be located reliably, the user deletes the whole insertion, or edits cross boundaries such that a trustworthy before-to-after mapping cannot be isolated.

### `CorrectionExtractor`

The extractor is a pure, testable component. It:

1. Tokenizes original and final text with `NLTokenizer`.
2. Computes `CollectionDifference` on tokens.
3. Coalesces adjacent removals and insertions into correction hunks.
4. Extracts the complete containing sentence as context, subject to a bounded character/token limit for exceptionally long sentences.
5. Preserves punctuation and formatting corrections because they can represent user preferences.
6. Rejects rewrites where changed content exceeds 50 percent of the original insertion.

Only correction hunks are persisted. Full original and final text snapshots are released after extraction.

### `CorrectionLearningService`

A dedicated actor owns the in-memory sample index and SQLite connection. It accepts extracted correction hunks, merges compatible samples, evicts excess samples, and retrieves relevant examples for Enhancement.

It maintains:

- A hash index by normalized original text for exact matches.
- An inverted token-to-sample-ID index for contextual candidates.
- Per-sample correction, match, and recency statistics.

Different replacements for the same original text remain separate when their contexts differ materially. This prevents a contextual correction such as a company name from becoming an unsafe global replacement.

### `EnhancementService`

Before building an Enhancement request, the service asks the in-memory index for relevant examples under a hard five-millisecond retrieval budget. The search proceeds in stages and stops as soon as the budget or result limit is reached:

1. Exact normalized occurrence matches.
2. Candidates from the inverted token index.
3. Bounded edit-distance comparison only over the small candidate set.
4. Ranking by textual relevance, correction frequency, and recent successful matching.

Short Chinese tokens do not receive broad fuzzy matching. Candidates with excessive length differences are rejected before edit-distance work.

At most five samples and approximately 300 prompt tokens are attached. If there is no high-confidence match, the request remains identical to today's request. Only samples actually selected for the prompt update `match_count` and `last_matched_at`.

## Storage and Privacy

All learned data is stored in the application's local Application Support directory. No CloudKit, iCloud container, AirType service, telemetry payload, or synchronization mechanism receives correction data.

Selected examples are sent only as part of a future Enhancement request to the model provider explicitly configured by the user. The setting description must make this distinction clear.

The SQLite database contains a `correction_samples` table:

| Column | Purpose |
| --- | --- |
| `id` | Stable sample identifier |
| `original` | User-corrected source fragment |
| `replacement` | User's replacement fragment |
| `normalized_original` | Exact-match key |
| `context_before` | Bounded sentence context before the edit |
| `context_after` | Bounded sentence context after the edit |
| `correction_count` | Number of compatible corrections merged into the sample |
| `match_count` | Number of times selected for an Enhancement prompt |
| `created_at` | Creation timestamp |
| `last_corrected_at` | Most recent user correction timestamp |
| `last_matched_at` | Most recent prompt selection timestamp, nullable |

The database also contains an `edit_sessions` diagnostic table with only session ID, target application bundle ID, original character count, status, and timestamps. It never contains the original or final full text, and rows are bounded to the 1,000 most recent sessions.

The database holds at most 1,000 correction samples. Compatible mappings are merged rather than duplicated. On overflow, eviction favors samples that were corrected more than once or recently selected. Samples corrected once, never selected, and oldest are removed first; creation time resolves remaining ties.

Application logs may contain durations, character counts, candidate counts, and error codes, but never inserted text, edited text, mappings, or contexts.

## Performance Requirements

The critical path is:

```text
recording -> transcription -> in-memory sample retrieval -> Enhancement -> insertion
```

The learning path is separate:

```text
session completion -> Accessibility snapshot -> background tokenization/diff -> actor index update -> SQLite transaction
```

Requirements:

- A new recording starts immediately and never awaits an older learning task.
- An Enhancement request may use the previous index state if a learning task is still running.
- Retrieval targets less than 3 ms and has a hard 5 ms budget at 1,000 samples.
- SQLite writes are incremental, serialized by the actor, and outside the voice-input path.
- Prompt examples are capped at five and approximately 300 tokens to limit provider-side latency.
- The entire sample index is loaded once and retained in memory; Enhancement does not read the database.

## Failure Handling

- Missing Accessibility permission follows current prompting and error behavior.
- Unsupported direct AX insertion falls back immediately to pasteboard insertion.
- Unreadable or unobservable AX targets insert successfully but do not learn.
- A lost target, invalid range, complete deletion, or cross-boundary rewrite discards the learning session.
- A diff changing more than 50 percent of the original is treated as a rewrite and is not stored in the word/phrase correction library.
- SQLite open or write failure disables persistence for that operation without interrupting voice input.
- Retrieval exceeding five milliseconds returns the best candidates already found.
- Prompt-budget overflow removes the lowest-ranked examples until within budget.

## Testing and Verification

### Unit tests

- Tokenization and diff extraction for English, Chinese, mixed text, punctuation, insertion, deletion, replacement, and adjacent multi-token edits.
- Sentence-context extraction and long-sentence bounding.
- Rewrite rejection at the 50-percent threshold.
- Sample merging, contextual separation, statistics, and deterministic eviction.
- Exact-match priority, bounded fuzzy matching, and protection against short-Chinese-token overmatching.
- Prompt selection capped at five samples and the configured token budget.
- Enhancement requests unchanged when no relevant sample exists.
- Insertion capability ladder using a protocol-backed Accessibility test double.
- Edit-session completion on focus departure and recording start, including non-blocking abandonment paths.

### Performance tests

A deterministic benchmark uses 1,000 samples and representative long transcription text. It records lookup duration, candidate count, and selected count. The product target is five milliseconds; CI uses a wider regression threshold to accommodate shared-machine variance, while local benchmark output reports the actual product-target result.

### Manual integration matrix

Direct insertion, observation, correction extraction, and fallback behavior are manually verified in:

- TextEdit
- Notes
- A browser-native text input and multiline text area
- At least one unsupported or partially supported text surface to exercise fallback

The final verification also confirms that the floating status window still reports recording and processing state, while the old Apply/Discard preview workflow is absent.

## Out of Scope

- Cloud synchronization of correction samples.
- Embedding-based or model-assisted local retrieval.
- Reconstructing edits from raw keyboard events.
- Learning from unobservable pasteboard fallback insertions.
- Treating large rewrites as vocabulary corrections.
- A user-facing correction-history editor in the first version.
