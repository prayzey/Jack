# Third-Party Notices

Jack is released under the MIT License (see `LICENSE`). It builds on the work below. Each item keeps its own license.

## Swift packages

Resolved in `Package.resolved` and fetched by Swift Package Manager at build time.

| Package | License | Source |
|---------|---------|--------|
| Sparkle | MIT | https://github.com/sparkle-project/Sparkle |
| TelemetryDeck SwiftSDK | MIT | https://github.com/TelemetryDeck/SwiftSDK |
| sentry-cocoa | MIT | https://github.com/getsentry/sentry-cocoa |
| WhisperKit | MIT | https://github.com/argmaxinc/WhisperKit |
| FluidAudio | Apache-2.0 | https://github.com/FluidInference/FluidAudio |
| LLM.swift | MIT | https://github.com/obra/LLM.swift |
| swift-ogg | Apache-2.0 | https://github.com/element-hq/swift-ogg |
| ogg-swift | MIT | https://github.com/vector-im/ogg-swift |
| opus-swift | MIT | https://github.com/vector-im/opus-swift |
| swift-transformers | Apache-2.0 | https://github.com/huggingface/swift-transformers |
| swift-jinja | Apache-2.0 | https://github.com/huggingface/swift-jinja |
| yyjson | MIT | https://github.com/ibireme/yyjson |
| swift-argument-parser, swift-asn1, swift-collections, swift-crypto, swift-syntax | Apache-2.0 | https://github.com/apple |

## Native helper built from source

`scripts/build-transcribe-helper.sh` clones and compiles these. They are not checked into this repository.

| Project | License | Source |
|---------|---------|--------|
| transcribe.cpp | MIT | https://github.com/handy-computer/transcribe.cpp |
| ggml | MIT | https://github.com/ggml-org/ggml |

## Derived work

The Pulse character animations in `Sources/Gilt/Resources/PulseCharacters/` derive from Lil Agents by Ryan Stephen, MIT License, https://github.com/ryanstephen/lil-agents. The full license text is shown in the app's About panel and in `Sources/Gilt/App/AppAttribution.swift`.

## Bundled fonts

All bundled fonts use the SIL Open Font License 1.1. The license texts live in `Sources/Gilt/Resources/Fonts/Licenses/`.

- Atkinson Hyperlegible, Braille Institute of America
- Instrument Sans, Rodrigo Fuenzalida and Jordan Egstad
- JetBrains Mono, JetBrains

## Models downloaded at runtime

Jack does not ship machine learning models. It downloads them from Hugging Face on first use, and each is governed by its own model card and license.

| Model | Used for | Source |
|-------|----------|--------|
| Whisper (via WhisperKit CoreML conversions) | Meeting transcription | https://huggingface.co/argmaxinc |
| NVIDIA Parakeet TDT 0.6B v3 (CC-BY-4.0) | Meeting transcription via FluidAudio | https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 |
| Parakeet unified EN 0.6B GGUF (derived from NVIDIA Parakeet, CC-BY-4.0) | Streaming dictation | https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf |
| Qwen3.5 4B (Apache-2.0), GGUF build by Unsloth | Local summaries and text assist | https://huggingface.co/Qwen/Qwen3.5-4B and https://huggingface.co/unsloth/Qwen3.5-4B-GGUF |
