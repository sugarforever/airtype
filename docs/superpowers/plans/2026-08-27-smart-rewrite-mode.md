# Smart Rewrite Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a selectable, shortcut-accessible Smart Rewrite mode with configuration gating and direct navigation to Enhancement settings.

**Architecture:** `EnhancementMode` remains in `CorrectionLearningCore` so prompt behavior is independently testable. `Settings` owns persisted mode and shortcut configuration, while `AppState` owns user actions and blocks Smart Rewrite before recording when Enhancement is incomplete. Dashboard navigation gains a settings-section target so every configuration prompt can open the relevant controls directly.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, HotKey, XCTest, Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-08-27-smart-rewrite-mode-design.md`

## Global Constraints

- Preserve Proofread as the default and retain its current prompt exactly.
- Reuse the existing Enhancement provider and request path.
- Support macOS 14 and add no dependencies.
- Follow test-first red-green cycles for behavior changes.

---

### Task 1: Prompt modes

**Files:**
- Modify: `Sources/CorrectionLearning/EnhancementPromptBuilder.swift`
- Test: `Tests/AirtypeTests/EnhancementPromptTests.swift`

**Interfaces:**
- Produces: `EnhancementMode` and `EnhancementPromptBuilder.prompt(mode:examples:vocabularySection:)`

- [ ] Add failing tests proving Smart Rewrite handles fillers, revisions, spoken instructions, ordering, and factual fidelity while Proofread remains unchanged.
- [ ] Run the focused test and confirm the new API or behavior fails.
- [ ] Implement the two prompt contracts with Proofread as the default argument.
- [ ] Run the focused tests and confirm they pass.

### Task 2: Persisted mode and readiness

**Files:**
- Modify: `Sources/Models/Settings.swift`
- Test: `Tests/AirtypeTests/TranscriptionRequestTests.swift`

**Interfaces:**
- Produces: `Settings.enhancementMode`, `Settings.enhancementConfigurationError`, and `Settings.isEnhancementConfigured`

- [ ] Add failing tests for mode persistence and incomplete provider, model, base URL, and API-key configurations.
- [ ] Run the focused tests and confirm they fail for missing settings behavior.
- [ ] Persist `EnhancementMode.rawValue` and centralize complete Enhancement readiness validation.
- [ ] Run the focused tests and confirm they pass.

### Task 3: Wire mode into Enhancement

**Files:**
- Modify: `Sources/Services/EnhancementService.swift`
- Test: `Tests/AirtypeTests/EnhancementServiceTests.swift`

**Interfaces:**
- Consumes: `Settings.enhancementMode`
- Produces: mode-specific system/developer prompt in the existing chat-completions request

- [ ] Add a failing request-boundary test that decodes the outgoing request and distinguishes Smart Rewrite from Proofread.
- [ ] Run it and confirm it fails because the selected mode is ignored.
- [ ] Pass the selected mode to `EnhancementPromptBuilder` for enhancement and configuration tests.
- [ ] Run the service tests and confirm they pass.

### Task 4: Direct settings navigation and recording guard

**Files:**
- Modify: `Sources/DashboardCore/DashboardModel.swift`
- Modify: `Sources/Services/MainWindowController.swift`
- Modify: `Sources/Views/MainView.swift`
- Modify: `Sources/Views/AirtypeSettingsView.swift`
- Modify: `Sources/AirtypeApp.swift`
- Test: `Tests/DashboardCoreTests/DashboardModelTests.swift`

**Interfaces:**
- Produces: `DashboardSettingsSection.enhancement`, `DashboardModel.showSettings(section:)`, and the Smart Rewrite preflight action

- [ ] Add a failing model test for selecting the Enhancement settings section.
- [ ] Run it and confirm the section target is missing.
- [ ] Add section navigation and scroll the settings view to the Enhancement card.
- [ ] Block recording when Smart Rewrite lacks configuration; set a notice and expose an action that calls `MainWindowController.showSettings(section: .enhancement)`.
- [ ] Run dashboard and focused app tests.

### Task 5: Mode controls and shortcut

**Files:**
- Modify: `Sources/Models/Settings.swift`
- Modify: `Sources/Services/HotkeyManager.swift`
- Modify: `Sources/Views/AirtypeSettingsView.swift`
- Modify: `Sources/Views/MenuBarView.swift`
- Modify: `Sources/AirtypeApp.swift`
- Test: `Tests/AirtypeTests/TranscriptionRequestTests.swift`

**Interfaces:**
- Produces: persisted configurable mode-switch shortcut and `AppState.selectEnhancementMode(_:)`

- [ ] Add failing persistence and mode-selection tests.
- [ ] Run them and confirm failure.
- [ ] Add a segmented mode picker with descriptions, a configurable shortcut recorder, and a menu-bar picker showing the current mode.
- [ ] Register the global shortcut and route all selection paths through configuration gating.
- [ ] Run focused tests.

### Task 6: Documentation and verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Documents the two modes, configuration requirement, menu control, and shortcut.

- [ ] Update feature and Enhancement documentation without claiming offline Smart Rewrite unless LM Studio is configured.
- [ ] Run the full Swift test suite in a clean scratch directory.
- [ ] Build the Airtype product with code signing disabled.
- [ ] Inspect `git diff --check`, the final diff, and branch status.

