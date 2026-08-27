# OpenRouter Qwen3 ASR Support Specification

AirType must offer OpenRouter as a cloud transcription provider alongside the existing providers.

- Selecting OpenRouter exposes an API-key field and a model picker.
- The only supported models in this release are `qwen/qwen3-asr-0.6b` and `qwen/qwen3-asr-1.7b`.
- The API key and selected model persist independently from other transcription-provider settings.
- Transcription uses `POST https://openrouter.ai/api/v1/audio/transcriptions` with bearer authentication and a JSON body containing the selected model plus base64-encoded audio in `input_audio`.
- Requests identify AirType to OpenRouter with `HTTP-Referer: https://www.airtype.space` and `X-OpenRouter-Title: AirType` so usage is attributed to the product.
- Successful responses return the `text` field. Missing keys, invalid responses, non-success HTTP responses, API errors, and empty transcriptions produce user-facing errors.
- Setup wizard and Settings both expose OpenRouter consistently.
- Existing providers and the user's unrelated working-tree files remain unchanged.
