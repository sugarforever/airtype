# Changelog

All notable changes to AirType are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [v0.11.1] - 2026-02-23

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
