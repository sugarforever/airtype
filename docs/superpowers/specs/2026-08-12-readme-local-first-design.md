# Local-first README redesign

## Goal

Make local transcription the first and clearest reason to use Airtype. A visitor should understand within the opening section that Airtype can transcribe entirely on their Mac without an API key or sending recordings to a transcription service.

## Audience

The README primarily serves prospective users evaluating Airtype. Contributor details remain available, but they should not compete with installation and everyday use.

## Information hierarchy

1. Product name and a one-sentence description.
2. A prominent local-first section covering privacy, offline transcription, and the absence of API keys.
3. A complete table of currently supported local models:
   - `Qwen3-ASR-0.6B-4bit` as the faster, lower-memory default.
   - `Qwen3-ASR-1.7B-4bit` as the larger quality-oriented option.
4. Download link and macOS requirement.
5. A short getting-started flow: install, grant permissions, choose and download a local model, then talk.
6. A compact feature list.
7. Cloud transcription and optional AI enhancement as secondary alternatives.
8. Minimal development and license information.

## Content changes

- Replace the current cloud-oriented opening with local-first messaging.
- Explain that model files are downloaded once and transcription runs on-device afterward.
- State only capabilities confirmed by the current implementation.
- Keep OpenAI, ElevenLabs, Mistral, and Doubao visible without giving each provider a long description.
- Consolidate confirmation, floating status, keyboard shortcuts, local history, and automatic updates into concise feature bullets or a small table.
- Remove the release-process walkthrough and versioning policy from the README.
- Avoid listing the unintegrated GLM adapter as a supported model.

## Accuracy constraints

- Do not claim that optional AI enhancement is local unless the user selects LM Studio or another local compatible endpoint.
- Distinguish local transcription from cloud transcription clearly.
- Do not promise performance or accuracy numbers that the repository does not measure.
- State the effective Xcode build requirement of macOS 14 Sonoma or later. The project deployment target takes precedence over the stale macOS 13 value in `Info.plist` and the current README.

## Validation

- Cross-check every local model name against `LocalMLXModel` in `Sources/Models/Settings.swift`.
- Check every provider name against `TranscriptionProvider`.
- Verify all retained links and Markdown structure.
- Review the final diff for duplication and ensure the local-first message appears before download and setup details.
