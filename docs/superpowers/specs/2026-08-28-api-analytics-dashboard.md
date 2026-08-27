# API Analytics Dashboard Specification

## Goal

Add a local analytics dashboard that measures transcription reliability and performance for every Airtype provider, with OpenRouter-specific token, cost, generation, and API-key usage data when available.

## Requirements

- Add an Analytics destination to the existing macOS dashboard sidebar.
- Record one metric for each non-streaming transcription attempt from the moment provider transcription begins until it succeeds or fails.
- Record timestamp, provider, model, client-observed response time, outcome, error category, and audio duration for all providers.
- For successful OpenRouter calls, additionally record input, output, and total tokens, billed cost in USD, and `X-Generation-Id` when returned.
- Show totals for calls, success rate, average latency, P95 latency, audio minutes, tokens, and cost.
- Show a per-model comparison and recent request list without storing audio or transcription text.
- Query `/api/v1/key` with the existing OpenRouter inference key to show daily, weekly, and monthly key usage and remaining limit. Do not require or store a Management API key.
- Display unsupported fields as unavailable rather than fabricating zero values. Local-model monetary cost may be shown as local/free, but is not an OpenRouter bill.
- “Accuracy” in version one means request success rate. Recognition accuracy is out of scope because no ground-truth transcript exists.
- Persist analytics locally. Existing historical requests cannot be backfilled.
- Keep the branch local; do not push it.

## Privacy

- Never persist API keys, audio bytes, raw transcription, enhanced text, prompts, or vocabulary in analytics records.
- Never print OpenRouter credentials in logs.
