# Airtype

Local and privacy first voice-to-text MacOS app that transcribes your voice and inserts text at your cursor — in any application. Hold a shortcut, speak, and Airtype inserts the transcription at your cursor in any application.

## Local by default

Airtype can transcribe entirely on your Mac with Apple MLX. No account or API key is required, and your recordings do not need to be sent to a transcription service. Download a model once, then use it for on-device transcription.

### Supported local models

| Model | Best for |
|---|---|
| `Qwen3-ASR-0.6B-4bit` | Faster transcription with lower memory use; the default choice |
| `Qwen3-ASR-1.7B-4bit` | A larger model when transcription quality is the priority |

Local transcription currently supports automatic language detection, English, and Chinese.

## Download

Get the latest release from [GitHub Releases](https://github.com/sugarforever/airtype/releases/latest) or [airtype.space](https://www.airtype.space/download).

**Requires macOS 14 Sonoma or later.**

## Getting started

1. Open the downloaded `.dmg`, then drag Airtype to Applications.
2. Launch Airtype and grant Microphone and Accessibility permissions when prompted.
3. In Settings, select **MLX Local**, choose a model, and download it.
4. Hold **Option + Space**, speak, and release to transcribe and insert the text.

Airtype runs in the menu bar. Keyboard shortcuts can be changed in Settings.

The main window organizes Airtype into four pages: **Home**, **History**, **Vocabulary**, and **Settings**. History keeps the 50 most recent complete transcription text entries locally on your Mac. Vocabulary lets you manage proper nouns for recognition-time guidance and optional enhancement.

## Features

- Fully local transcription with no API key required
- Push-to-talk and toggle-recording shortcuts
- Text insertion at the active cursor through the system pasteboard and Command-V
- A floating panel for recording and transcription status
- Up to 50 recent transcriptions stored locally
- Optional AI cleanup for grammar, punctuation, and formatting
- Two Enhancement writing modes: conservative Proofread and thought-aware Smart Rewrite
- Signed automatic updates with in-app installation and relaunch

| Action | Default shortcut |
|---|---|
| Push to talk | **Option + Space** |
| Toggle recording | **Option + Shift + Space** |
| Switch writing mode | **Control + Option + Space** |

## Cloud transcription and enhancement

Local transcription is the simplest private setup, but Airtype also supports cloud transcription through **OpenAI**, **ElevenLabs**, **Mistral**, and **Doubao**. These providers require their own credentials and send audio to the selected service.

Optional AI enhancement can clean up a completed transcription without changing its intent. It supports OpenAI-compatible providers including OpenAI, OpenRouter, Together AI, Groq, DeepSeek, Moonshot AI, z.ai, Azure OpenAI, Cloudflare Workers AI, custom endpoints, and LM Studio for local enhancement.

Enhancement offers two writing modes. **Proofread** fixes recognition, punctuation, casing, and formatting while preserving the speaker's wording. **Smart Rewrite** removes filler and false starts, keeps the final version of spoken revisions, follows spoken editing instructions, and organizes out-of-order thoughts without inventing details. Choose the mode in Settings or the menu bar, or switch with the configurable global shortcut. Smart Rewrite requires a complete Enhancement provider, model, endpoint, and API-key configuration; Airtype links directly to those settings when setup is incomplete. LM Studio can keep this step local when a compatible local model is running.

Proper nouns and previously stored correction samples are kept in a local SQLite database. Airtype no longer observes edits in external input fields. The learned-corrections interface is currently removed; existing samples are preserved locally and may still provide a small set of relevant examples during Enhancement. Enhancement receives only bounded vocabulary guidance and relevant correction examples. A bounded selection of proper nouns is automatically sent to supported transcription backends. The local databases themselves never leave the Mac.

### Vocabulary during transcription

Airtype automatically uses your existing proper nouns to guide recognition, even when Enhancement is off. Manage terms in **Vocabulary**; there is no separate Settings toggle. With MLX Local the vocabulary stays on your Mac; cloud transcription sends the selected terms along with your audio.

| Backend | Recognition-time guidance |
| --- | --- |
| MLX Local (both Qwen3-ASR models) | Native `context` text, entirely on-device |
| OpenAI (`gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`) | `prompt` text; soft guidance, not forced replacements |
| ElevenLabs (`scribe_v2`) | `keyterms`; incurs an additional 20% transcription surcharge under current provider pricing |
| Mistral (`voxtral-mini-2602`, `voxtral-mini-latest`) | `context_bias`; optimized for English, other languages experimental |
| Doubao (SeedASR bidirectional streaming) | JSON-encoded hotwords in `request.corpus.context` |

Airtype selects newer terms first, removes duplicates and invalid entries, and sends at most 100 terms with additional provider-specific byte/length limits. OpenAI Whisper and Doubao use especially conservative budgets, so only a small subset may fit. Oversized terms are skipped rather than cut in half. Empty vocabularies and unsupported model variants add no optional parameters. Vocabulary changes apply to the next recording/session, including reused Doubao preconnections; OpenAI chunks share one snapshot. Hints can improve proper-noun recognition but do not guarantee accuracy or constrain the transcript to the vocabulary.

Provider references: [MLX context support](https://github.com/Blaizzy/mlx-audio-swift/pull/126), [OpenAI prompting](https://platform.openai.com/docs/guides/speech-to-text), [ElevenLabs keyterms and pricing conditions](https://elevenlabs.io/docs/api-reference/speech-to-text/convert), [Mistral context biasing](https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription), [Doubao streaming API](https://www.volcengine.com/docs/6561/1354869?lang=en).

## Development

Requirements:

- Xcode 16.4 or later
- macOS 14 or later

```bash
open Airtype.xcodeproj
```

Run the `Airtype` scheme with **Command + R**. Swift Package Manager resolves the project dependencies.

### Releasing

Tagged releases continue to publish a notarized DMG through GitHub Releases. The release workflow also generates a signed Sparkle `appcast.xml`, which lets installed copies of Airtype check for, download, and install updates.

Sparkle's private EdDSA key is stored in the repository's `SPARKLE_PRIVATE_KEY` Actions secret. Its matching public key is committed as `SUPublicEDKey` in `Info.plist`. Do not rotate either key independently; existing installations reject updates signed with a different key.

## License

MIT
