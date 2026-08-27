# Qwen3-ASR Full Series Design

Airtype will support every MLX Community Qwen3-ASR model variant in the published 0.6B and 1.7B families: 4-bit, 5-bit, 6-bit, 8-bit, and bf16.

The model enum remains the single source of truth for picker identity, persistence, Hugging Face repository selection, download URL construction, installation bookkeeping, removal, and transcription. Each new case uses the exact MLX Community repository suffix in its persisted raw value.

Existing installations may contain the legacy raw value `Qwen3-ASR-1.7B`, even though that selection already points to the 4-bit repository. Settings initialization must migrate both the selected model and installed-model records to `Qwen3-ASR-1.7B-4bit`. Unknown future or removed values continue to fall back to the default 0.6B 4-bit model.

The Settings and setup-wizard pickers already enumerate `LocalMLXModel.allCases`; they should expose all ten variants without a second model catalog. The README will list each supported repository and approximate download size, while keeping 0.6B 4-bit as the default recommendation.

No inference algorithm, model weights, quantization conversion, custom download source, audio handling, or model-quality claim is added in this change.
