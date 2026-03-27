# Airtype

Voice-to-text for macOS. A menu bar app that transcribes your voice and inserts text at your cursor — in any application.

## Download

Get the latest release from [GitHub Releases](https://github.com/sugarforever/airtype/releases/latest) or from [airtype.space](https://www.airtype.space/download).

**Requirements:** macOS 13 Ventura or later.

## Getting Started

### 1. Install

1. Open the downloaded `.dmg` file
2. Drag Airtype to your Applications folder
3. Launch Airtype — it appears in your menu bar

### 2. Grant Permissions

Airtype requires two system permissions:

| Permission | Where to enable | Why |
|---|---|---|
| **Microphone** | System Settings > Privacy & Security > Microphone | To record your voice |
| **Accessibility** | System Settings > Privacy & Security > Accessibility | To insert text at your cursor via paste |

You'll be prompted on first launch. If you skip, a banner in Settings will remind you.

### 3. Add an API Key

Open Settings from the menu bar icon and configure a transcription provider:

| Provider | API Key Format | Get a Key |
|---|---|---|
| **OpenAI** | `sk-...` | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |
| **ElevenLabs** | `xi-...` | [elevenlabs.io/app/settings/api-keys](https://elevenlabs.io/app/settings/api-keys) |
| **Mistral** | — | [console.mistral.ai/api-keys](https://console.mistral.ai/api-keys) |
| **Doubao** (streaming) | App ID + Access Token + Resource ID | [console.volcengine.com/speech/app](https://console.volcengine.com/speech/app) |

### 4. Talk

Hold **Option + Space** (default), speak, release. Your words appear at the cursor.

## How It Works

1. **Record** — Hold the hotkey to record (or toggle on/off with Option+Shift+Space)
2. **Transcribe** — Audio is sent to your chosen provider and transcribed
3. **Enhance** (optional) — An LLM cleans up grammar, punctuation, and formatting while preserving your intent
4. **Insert** — Text is pasted at your cursor in whatever app is focused

No account, no cloud service beyond the API. Your keys, your data.

## Features

### Transcription Providers

- **OpenAI** — Models: `gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`. Supports chunked upload for long recordings.
- **ElevenLabs** — Models: `scribe_v2`, `scribe_v1`
- **Mistral** — Models: `voxtral-mini-2602`, `voxtral-mini-latest`
- **Doubao** — Real-time streaming transcription via WebSocket. Supports Chinese, English, Japanese, Korean, Spanish, French, Russian.

### AI Enhancement (Optional)

After transcription, an LLM can clean up the text — fixing grammar, punctuation, homophones, and casing without changing what you said. Supports 10+ providers:

OpenAI, OpenRouter, Together AI, Groq, DeepSeek, Moonshot AI, z.ai, Azure OpenAI, Cloudflare Workers AI, LM Studio (local, no API key needed), or any custom OpenAI-compatible endpoint.

### Confirm Before Inserting

Enable "Confirm before inserting" in Settings to preview and edit the transcription before it's inserted. The floating window shows the result with an editable text area — make corrections, then click Apply.

### Keyboard Shortcuts

| Action | Default Shortcut | Description |
|---|---|---|
| Push-to-talk | **Option + Space** | Hold to record, release to transcribe |
| Toggle recording | **Option + Shift + Space** | Press to start, press again to stop |

Shortcuts are re-bindable in Settings.

### Floating Window

A compact floating panel shows recording status, streaming transcription, and processing progress. It can be positioned in any corner of the screen. Click to expand for a detailed view.

### Transcription History

Every transcription is saved locally (up to 50 entries). Access via "Recent Transcriptions" in the menu bar. Each entry shows the text, timestamp, and whether it was successfully inserted — so you never lose text if insertion fails. Copy any entry to your clipboard with one click.

### Auto-Update

Airtype checks for updates automatically and shows a banner in Settings when a new version is available.

## Development

### Prerequisites

- Xcode 16.4+
- macOS 13.0+

### Build & Run

```bash
open Airtype.xcodeproj
# Run the Airtype scheme (Cmd+R)
```

Dependencies (resolved via SPM): [HotKey](https://github.com/soffes/HotKey)

## Release Process

Releases are automated via GitHub Actions. Pushing a git tag triggers the workflow which builds, signs, notarizes, and publishes to GitHub Releases.

1. Update `CHANGELOG.md` with the new version entry
2. Tag and push:
   ```bash
   git tag v0.12.0
   git push origin v0.12.0
   ```
3. GitHub Actions automatically builds, signs, notarizes, creates a DMG, and publishes a GitHub Release with the DMG attached.

### Version Scheme

Follow [semver](https://semver.org):
- **Patch** (v0.1.1) — bug fixes
- **Minor** (v0.2.0) — new features
- **Major** (v1.0.0) — breaking changes or public launch

## License

MIT
