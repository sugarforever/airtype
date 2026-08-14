# Airtype Dashboard, History, and Vocabulary Design

## Goal

Expand Airtype's compact settings window into a minimal, resizable macOS dashboard. The dashboard makes recent transcriptions and locally learned corrections visible, and lets users maintain a simple global list of correctly spelled proper nouns for Enhancement.

The design borrows the spatial structure of Typeless—a narrow sidebar and a focused content area—without its promotional cards, use-case grid, or dense statistics.

## Product Principles

- Keep the interface minimal and native to macOS.
- Preserve the speed of transcription and direct insertion.
- Keep history, learned corrections, and vocabulary local.
- Make learned behavior inspectable and removable.
- Ask users only for correct terminology, not likely misrecognitions.
- Build vocabulary as an isolated module so ranking and scoping can evolve later.

## Navigation and Window

The main window becomes resizable and uses a two-column layout:

- A narrow, fixed-width sidebar.
- A flexible content area.

The sidebar has four primary destinations:

1. Home
2. History
3. Vocabulary
4. Settings

The existing settings content moves under Settings. Recent transcription history is integrated into the main window; the separate history window is retired. The UI uses Airtype's existing system background, control background, separator, label, and brand-green colors in both light and dark appearances.

## Home

Home is a lightweight status page rather than a second settings page. It contains:

- Ready or setup-required state.
- The primary recording shortcut and a short instruction.
- Today's transcription count.
- Today's learned-correction count.
- The two most recent transcription entries.

Home does not show promotional content, use-case cards, or configuration controls.

## History

History keeps the existing limit of the 50 most recent transcriptions and continues using `TranscriptionHistory` storage.

Each entry is a full-text card:

- Text is never truncated or line-limited.
- Newest entries appear first.
- Only relative time and a copy control are shown.
- Insertion status is not shown because it does not help the user locate the inserted text.
- Copy uses the `square.on.square` SF Symbol with no background.
- Successful copying temporarily changes the icon to a brand-green `checkmark`.

The page supports in-memory search and clearing all history. Clear uses the same brand-green text and light-green background as Airtype's current secondary action buttons and requires confirmation. A lazy list renders only entries near the viewport so long text does not create unnecessary layout work.

## Vocabulary

Vocabulary contains two segmented tabs: Proper Nouns and Learned Corrections.

### Proper Nouns

Users enter only the correct spelling, such as `Cloudflare`, `ReactNative`, or `小木头`. The first version does not ask for a common misrecognition and does not support application or language scopes. Every term is global.

Proper nouns use a compact tag-wall layout:

- Small system font and regular weight.
- Natural wrapping for terms of different lengths.
- Alphabetical or localized ordering in the visible tag wall.
- Search filters the in-memory snapshot.
- A delete affordance appears on hover or selection.
- Creation time is not displayed.

Adding a term trims surrounding whitespace and rejects empty or duplicate normalized values. Terms are stored only on the Mac.

### Learned Corrections

Learned corrections use a compact mapping list because direction matters:

`recognized text → corrected text`

Each row shows the mapping and correction count. Context is hidden by default and expands on demand. Users can search recognized or corrected text and delete incorrect samples. Samples cannot be edited in the first version because editing would conflict with stored context and aggregate statistics.

Deleting a learned correction removes it from the in-memory index immediately and persists deletion asynchronously. It must no longer participate in subsequent Enhancement requests.

## VocabularyCore Module

Proper-noun behavior is implemented as an isolated `VocabularyCore` module with these boundaries:

- `VocabularyTerm`: immutable public term model.
- `VocabularyStoring`: persistence protocol.
- `SQLiteVocabularyStore`: SQLite implementation.
- `VocabularyRepository`: validation, normalization, duplicate prevention, add, delete, load, and prompt selection.
- `VocabularyPromptBuilder`: renders selected terms into Enhancement guidance.

The UI depends on repository operations and models, not SQLite. Enhancement depends on the prompt builder, not UI state. Future ranking, per-application scope, language scope, aliases, or usage statistics can be added within this module without changing the dashboard or Enhancement boundary.

## Storage

The implementation uses the incremental-storage approach:

- Transcription history remains in its current lightweight `UserDefaults` representation with a 50-entry limit.
- Learned corrections remain in the existing local SQLite database and `correction_samples` table.
- A new `vocabulary_terms` table is added to the same SQLite database.
- API keys and other sensitive settings remain in their current settings storage and are not copied into this database.

The proper-noun schema stores an ID, original display value, normalized value, and creation time. The normalized value is unique.

## Enhancement Integration

Proper-noun selection is deliberately simple in the first version:

1. Read terms in reverse creation order, newest first.
2. Append complete terms until the configured total budget would be exceeded.
3. Stop immediately at the budget boundary.

The initial proper-noun budget is 300 estimated tokens. Selection does not use fuzzy matching, input relevance, usage counts, or result scanning. Learned-correction examples retain their existing separate 300-token budget and retrieval behavior.

Vocabulary loading and prompt construction happen immediately before Enhancement. They do not run on the transcription, Accessibility insertion, or edit-observation critical path. If no terms fit or the store is unavailable, the existing Enhancement prompt is preserved.

## State and Data Flow

A main-actor dashboard model owns navigation and page snapshots. It requests asynchronous operations from the history and vocabulary services and exposes stable, filtered arrays to SwiftUI.

Views are separated by destination rather than added to the existing monolithic `MainView`:

- Dashboard container and sidebar.
- Home view.
- History view.
- Vocabulary view with proper-noun and learned-correction child views.
- Settings view containing the existing configuration sections.

Search operates on loaded in-memory snapshots. SwiftUI view bodies perform no SQLite queries, token estimation, or filtering of large collections. Lists use stable IDs and lazy containers.

## Errors and Degraded Operation

- SQLite failures produce a local error state on Vocabulary without blocking recording, transcription, direct insertion, or base Enhancement.
- A failed add or delete restores the visible snapshot or reloads it from the store.
- Duplicate and empty terms produce inline validation messages.
- Clipboard failure leaves the copy icon unchanged.
- Clearing history requires explicit confirmation.
- Empty history, empty vocabulary, empty learned corrections, and no search results each have quiet, specific empty states.

No content text is written to debug logs.

## Performance Requirements

- Dashboard navigation and in-memory search must feel immediate.
- SQLite work runs outside view rendering and the insertion path.
- Proper-noun prompt selection is linear in the number of newest terms consumed and stops at 300 estimated tokens.
- Learned-correction retrieval retains its existing 5 ms time budget.
- History uses lazy rendering for full-length cards.
- The dashboard must remain usable at its minimum size and in both light and dark mode.

## Testing

Unit tests cover:

- Proper-noun trimming, normalization, duplicate rejection, insertion, deletion, and persistence.
- Reverse-creation ordering for Enhancement selection.
- Strict token-budget enforcement without partial terms.
- Empty and unavailable-store fallback preserving the base Enhancement prompt.
- Learned-correction deletion removing a sample from retrieval.
- History search, clearing, and copy-state behavior in the dashboard model.
- SQLite failure degradation without impacting core transcription services.
- Loading, searching, and prompt construction with hundreds of proper nouns and 1,000 learned corrections.

UI and integration verification cover:

- Sidebar navigation and window resizing.
- Full, untruncated history text.
- `square.on.square` copy feedback.
- Clear confirmation and global button colors.
- Tag wrapping and hover deletion.
- Expandable learned-correction context.
- Empty, error, light-mode, and dark-mode states.

## Out of Scope

- User-entered `misrecognition → correction` mappings.
- Editing learned correction mappings.
- Per-application or per-language vocabulary.
- Vocabulary relevance ranking, fuzzy matching, phonetic matching, or usage statistics.
- Increasing history retention beyond 50 entries.
- Storing or displaying audio.
- Cloud synchronization or export.
