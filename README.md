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

## Features

- Fully local transcription with no API key required
- Push-to-talk and toggle-recording shortcuts
- Optional preview and editing before text is inserted
- A floating panel for recording and transcription status
- Up to 50 recent transcriptions stored locally
- Optional AI cleanup for grammar, punctuation, and formatting
- Automatic update checks

| Action | Default shortcut |
|---|---|
| Push to talk | **Option + Space** |
| Toggle recording | **Option + Shift + Space** |

## Cloud transcription and enhancement

Local transcription is the simplest private setup, but Airtype also supports cloud transcription through **OpenAI**, **ElevenLabs**, **Mistral**, and **Doubao**. These providers require their own credentials and send audio to the selected service.

Optional AI enhancement can clean up a completed transcription without changing its intent. It supports OpenAI-compatible providers including OpenAI, OpenRouter, Together AI, Groq, DeepSeek, Moonshot AI, z.ai, Azure OpenAI, Cloudflare Workers AI, custom endpoints, and LM Studio for local enhancement.

## Development

Requirements:

- Xcode 16.4 or later
- macOS 14 or later

```bash
open Airtype.xcodeproj
```

Run the `Airtype` scheme with **Command + R**. Swift Package Manager resolves the project dependencies.

## License

MIT
