# UI Usability Implementation Plan

**Goal:** Apply the accepted SwiftUI review: accurate dashboard readiness, actionable Home guidance, accessible floating controls, reduced motion, and readable Vocabulary layout.

**Architecture:** Derive readiness from provider configuration and permission snapshots in DashboardCore. MainView refreshes system permissions and supplies shared readiness to dashboard views. Keep recording behavior and existing glass styling unchanged.

**Tech Stack:** SwiftUI, AppKit, AVFoundation, XCTest; macOS 14+.

**Spec:** The five improvements accepted in this task's review.

## Tasks

- [x] Add readiness cases and regression tests in DashboardModel.swift and DashboardModelTests.swift. Exercise missing provider, microphone, Accessibility, all-ready, and every combination of missing prerequisites. Run `AIRTYPE_CORE_TESTS=1 swift test --scratch-path .build/ui-core-tests --filter DashboardModelTests` before and after implementation.
- [x] Wire MainView permission refresh on appearance and application activation; share readiness with HomeView, DashboardSidebar, and AirtypeSettingsView. Home offers setup/permission actions and View history.
- [x] Replace FloatingView's container gesture with labeled controls. Respect Reduce Motion in expansion, streaming scroll, recording dot, and AppKit resizing. Preserve panel dragging and recording actions.
- [x] Move Vocabulary's privacy explanation below the title with readable secondary styling and wrapping.
- [x] Run full Swift tests, macOS build, and `git diff --check`. Review scope and document any runtime verification limits. Leave unrelated work untouched.


## Verification

- The existing core-test cache contained a relocated module cache; a fresh `.build/ui-core-tests` scratch directory avoided changing or deleting it.
- Readiness tests failed for the missing type before implementation, then all four DashboardModel tests passed.
- Full `swift test`: 104 tests passed, zero failures.
- Unsigned Debug Xcode build succeeded. Existing dependency/module-cache and deployment-target warnings are unrelated to these changes.
- `git diff --check` passed.
- Live VoiceOver, permission dialogs, and visual checks at different window sizes remain manual checks; no system permissions or user preferences were changed.
