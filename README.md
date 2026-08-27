# Airtype

Local and privacy first voice-to-text MacOS app that transcribes your voice and inserts text at your cursor — in any application. Hold a shortcut, speak, and Airtype inserts the transcription at your cursor in any application.

## Local by default

Airtype can transcribe entirely on your Mac with Apple MLX. No account or API key is required, and your recordings do not need to be sent to a transcription service. Download a model once, then use it for on-device transcription.

### Supported local models

| Model | Approx. download | Best for |
|---|---:|---|
| `Qwen3-ASR-0.6B-4bit` | 0.71 GB | Lowest memory use; the default choice |
| `Qwen3-ASR-0.6B-5bit` | 0.79 GB | Compact 0.6B model with higher precision |
| `Qwen3-ASR-0.6B-6bit` | 0.86 GB | Middle ground for the 0.6B model |
| `Qwen3-ASR-0.6B-8bit` | 1.01 GB | Higher-precision 0.6B model |
| `Qwen3-ASR-0.6B-bf16` | 1.57 GB | Unquantized 0.6B model |
| `Qwen3-ASR-1.7B-4bit` | 1.61 GB | Larger model with the lowest 1.7B memory use |
| `Qwen3-ASR-1.7B-5bit` | 1.82 GB | Compact 1.7B model with higher precision |
| `Qwen3-ASR-1.7B-6bit` | 2.04 GB | Middle ground for the 1.7B model |
| `Qwen3-ASR-1.7B-8bit` | 2.47 GB | Higher-precision 1.7B model |
| `Qwen3-ASR-1.7B-bf16` | 4.08 GB | Unquantized 1.7B model; highest resource use |

Download sizes are approximate and do not include temporary files or duplicate cache copies. Higher precision increases resource use but does not guarantee better recognition for every recording.

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
- Signed automatic updates with in-app installation and relaunch

| Action | Default shortcut |
|---|---|
| Push to talk | **Option + Space** |
| Toggle recording | **Option + Shift + Space** |

## Cloud transcription and enhancement

Local transcription is the simplest private setup, but Airtype also supports cloud transcription through **OpenAI**, **ElevenLabs**, **Mistral**, and **Doubao**. These providers require their own credentials and send audio to the selected service.

Optional AI enhancement can clean up a completed transcription without changing its intent. It supports OpenAI-compatible providers including OpenAI, OpenRouter, Together AI, Groq, DeepSeek, Moonshot AI, z.ai, Azure OpenAI, Cloudflare Workers AI, custom endpoints, and LM Studio for local enhancement.

Proper nouns and previously stored correction samples are kept in a local SQLite database. Airtype no longer observes edits in external input fields. The learned-corrections interface is currently removed; existing samples are preserved locally and may still provide a small set of relevant examples during Enhancement. Enhancement receives only bounded vocabulary guidance and relevant correction examples. A bounded selection of proper nouns is automatically sent to supported transcription backends. The local databases themselves never leave the Mac.

### Vocabulary during transcription

Airtype automatically uses your existing proper nouns to guide recognition, even when Enhancement is off. Manage terms in **Vocabulary**; there is no separate Settings toggle. With MLX Local the vocabulary stays on your Mac; cloud transcription sends the selected terms along with your audio.

| Backend | Recognition-time guidance |
| --- | --- |
| MLX Local (all Qwen3-ASR models) | Native `context` text, entirely on-device |
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
