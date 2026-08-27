# Changelog

All notable changes to AirType are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- Smart Rewrite Enhancement mode removes speech noise, applies spoken revisions and editing instructions, and organizes thoughts while preserving factual fidelity
- Visible Proofread and Smart Rewrite controls in Settings and the menu bar, plus a configurable global shortcut for switching modes
- Smart Rewrite configuration checks with a direct shortcut to the Enhancement settings section when the provider or model is incomplete

### Changed
- Proofread remains the default Enhancement mode and preserves the existing conservative correction behavior

## [v0.14.2] - 2026-08-27

### Added
- Enhancement settings can send a small real request to test the configured API key, Base URL, model, and OpenAI chat-completions compatibility

### Changed
- Enhancement failures now distinguish authentication, endpoint/model, malformed configuration, empty completion, and incompatible response errors

### Fixed
- Enhancement settings keep API configuration controls mounted so the enable switch responds without rebuilding and relaying out the entire section

## [v0.14.1] - 2026-08-26

### Added
- Signed automatic updates powered by Sparkle, including background checks, downloads, installation, and relaunch
- Manual “Check for Updates” actions in the menu bar and Settings

### Changed
- GitHub Release publishing now generates and uploads a signed Sparkle appcast alongside the notarized DMG

## [v0.14.0] - 2026-08-26

### Added
- Resizable dashboard with Home, History, Vocabulary, and Settings navigation
- Home page with setup guidance, recording shortcuts, today's transcription count, and recent transcriptions
- Searchable transcription history with full text, copy feedback, and confirmation before clearing
- Local proper-noun vocabulary with search, add, and delete controls
- Vocabulary hints for local Qwen3-ASR and supported OpenAI, ElevenLabs, Mistral, and Doubao transcription models, as well as optional text enhancement
- Shared local-model installation progress across setup and settings, including live download percentages and a separate model-loading phase

### Changed
- New installations default to MLX Local transcription; existing provider selections are preserved
- Saved vocabulary is applied automatically, including when text enhancement is disabled
- Simplified recording flow by removing the editable preview-before-insert mode; completed transcriptions are inserted directly
- Improved dashboard spacing, settings layout, and vocabulary tag presentation

### Fixed
- Sidebar navigation now responds across the entire row, including blank padding, with consistently aligned icons and labels
- Local-model download progress updates during file transfer instead of appearing stalled
- Removing a local model now clears its installed snapshot and associated Hugging Face cache; removal failures are reported without incorrectly marking the model uninstalled
- Clipboard and paste-event failures are surfaced instead of silently reporting successful text insertion
- Release notes are extracted from the matching CHANGELOG section and must be non-empty before a GitHub Release is created

### Privacy
- Vocabulary is stored locally. When using cloud transcription or optional cloud text enhancement, selected terms are sent to the configured provider; vocabulary hints for local Qwen3-ASR stay on-device
- Removed transcript and clipboard contents from routine text-insertion diagnostics and stopped writing the legacy temporary debug log

## [v0.13.0] - 2026-08-12

### Added
- Fully local speech transcription on Apple Silicon using MLX
- Qwen3-ASR 0.6B 4-bit and 1.7B 4-bit model selection
- In-app model download, installation status, removal, and local cache management
- Automatic language detection with optional Chinese or English selection

### Changed
- Setup and Voice Input settings now support transcription providers that do not require API keys
- Pinned the MLX Audio dependency to a verified revision for reproducible release builds

## [v0.12.0] - 2026-03-27

### Added
- Transcription history: persists recent transcriptions locally so text is never lost
- "Recent Transcriptions" window accessible from menu bar with copy-to-clipboard support
- GitHub Actions release workflow (replaces CircleCI)
- GitHub Releases for distribution (replaces R2)

### Changed
- Update checker now reads from GitHub Releases API

## [v0.11.2] - 2026-02-23

### Added
- Editable preview text in floating window confirm mode
- Auto-expand floating panel when recording starts in preview mode

### Fixed
- Apply button now correctly inserts text into the previously focused app

## [v0.11.0] - 2026-02-19

### Added
- Streaming transcription with Doubao and real-time text display
- Floating panel preview for streaming transcription
- Changelog and release notes published to R2

### Changed
- Show empty/short recordings as notices instead of errors
- WebSocket management: actor isolation, pre-connect without server timeout, ping keepalive, thread-safe logging

## [v0.10.0] - 2026-02-11

### Changed
- Voice service picker now uses a dropdown instead of a segmented control

## [v0.9.0] - 2026-02-11

### Added
- Open settings window when Dock icon is clicked

## [v0.8.0] - 2026-02-11

### Fixed
- Setup wizard UX: Dock icon visibility, mic permission, and accessibility prompt

## [v0.7.1] - 2026-02-11

### Fixed
- DMG creation for headless CI (replaced AppleScript with hdiutil)

## [v0.7.0] - 2026-02-11

### Added
- Drag-to-install UI in DMG installer

## [v0.6.0] - 2026-02-11

### Changed
- Upgraded CI to Xcode 26.2 for native macOS 26 SDK rendering

## [v0.5.0] - 2026-02-11

### Added
- Automatic update checker with in-app banner
- Version metadata published to R2 on release

## [v0.4.0] - 2026-02-11

### Added
- Setup wizard for first-time users

## [v0.3.0] - 2026-02-11

### Changed
- Updated app icon and applied brand color (#34D399) across UI
- Improved API key link discoverability
