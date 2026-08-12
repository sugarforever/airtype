# Local-first README Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the project README so local, private transcription and the complete supported local-model list are immediately visible, while removing homepage-level maintenance detail and repetitive feature explanations.

**Architecture:** This is a documentation-only change. Replace the current cloud-first information hierarchy in `README.md` with the approved local-first hierarchy, retaining concise cloud-provider, development, and license references for completeness.

**Tech Stack:** GitHub-flavored Markdown, repository source-of-truth enums in Swift.

## Global Constraints

- List only `Qwen3-ASR-0.6B-4bit` and `Qwen3-ASR-1.7B-4bit` as supported local transcription models.
- Do not list the unintegrated GLM adapter.
- Clearly distinguish local transcription from optional cloud transcription and optional AI enhancement.
- Do not claim measured speed, memory, or accuracy figures.
- State macOS 14 Sonoma or later, matching `MACOSX_DEPLOYMENT_TARGET = 14.0`.
- Do not create or push a version tag.

---

### Task 1: Rewrite and validate the README

**Files:**
- Modify: `README.md`
- Reference: `Sources/Models/Settings.swift`
- Reference: `Airtype.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `LocalMLXModel`, `TranscriptionProvider`, and the project deployment target.
- Produces: A concise, user-facing project homepage with a local-first opening.

- [x] **Step 1: Record the pre-change acceptance failure**

Run a shell check that requires the local-first heading, both model names, macOS 14, and the absence of the release-process section. Confirm it fails against the existing README.

- [x] **Step 2: Rewrite `README.md`**

Use this exact section order:

1. `# Airtype`
2. Opening description and `## Local by default`
3. `### Supported local models`
4. `## Download`
5. `## Getting started`
6. `## Features`
7. `## Cloud transcription and enhancement`
8. `## Development`
9. `## License`

Keep setup to four actions: install, grant Microphone and Accessibility permissions, select and download a local model, then use Option + Space. Remove the release-process walkthrough, semantic-versioning explanation, individual cloud API-key table, and long per-feature prose.

- [x] **Step 3: Run content acceptance checks**

Verify that the README contains both exact local-model names, names all four cloud transcription providers, states macOS 14, places `## Local by default` before `## Download`, and contains no `## Release Process` section.

- [x] **Step 4: Run Markdown and diff checks**

Run `git diff --check -- README.md`, inspect all links and headings, compare claims with `Sources/Models/Settings.swift`, and review the complete diff for duplication.

- [ ] **Step 5: Commit only the README and plan**

Stage `README.md` and this plan file only. Commit with the message `Rewrite README around local transcription`. Do not stage unrelated untracked files, create a version tag, or push.
