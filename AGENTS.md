# Repository Guidelines

## Project Structure & Module Organization

OtoChef is a SwiftPM macOS app with a Python media worker. The app target lives in `Sources/OtoChefApp`, organized by `App`, `Domain`, `Views`, `Stores`, and `Services`. `Sources/OtoChefApp/Domain` contains Swift domain and configuration type definitions such as app settings and job records; it is not a directory for Whisper/WhisperKit model files. Swift tests live in `Tests/OtoChefAppTests`. The Python worker package is in `worker/otochef_worker`, with pytest tests in `worker/tests`. App bundle resources live in `Resources`; `script/build_and_run.sh` expects `Resources/AppIcon.icns` and copies it into `dist/OtoChef.app`. Setup and run helpers are in `script/`. Design notes and implementation plans are under `docs/superpowers/`. Keep sample media and local test inputs out of app or worker source directories; local media scratch directories such as `测试内容/` and `local-media/` are ignored and must stay out of Git.

## ASR, Models, and Video Output

ASR is native Swift using WhisperKit/Core ML from `argmaxinc/argmax-oss-swift`; do not add new faster-whisper dependencies or route normal macOS transcription through Python. The Swift app writes `transcript.ja.json`, and the Python worker continues with translation, subtitle rendering, and optional FFmpeg video output. The Python worker no longer has a faster-whisper fallback; if `transcript.ja.json` is missing, the worker should fail clearly and tell the user to run the native ASR step first. Local WhisperKit/Core ML model files live under the ignored project-root directory `Models/whisperkit`; keep downloaded model files out of Git. Current expected model names are `openai_whisper-large-v3`, `openai_whisper-large-v3_947MB`, `large-v3-v20240930_626MB`, and `tiny`.

WhisperKit model choices are user-facing quality tiers in `ASRSettings.whisperKitModelChoices`; keep labels, defaults, and tests aligned when changing them. Keep VAD strategy uniform across model tiers. WhisperKit concurrent chunk processing is capped by `ASRSettings.maxWhisperKitConcurrentSegments`; keep the UI stepper, default settings, persisted-settings migration, and `WhisperKitTranscriptionService.effectiveConcurrentWorkerCount` in sync. If parallel WhisperKit output has suspicious leading gaps or large timing gaps, the native service should retry sequentially rather than special-casing one model tier.

Subtitle output is user-selected through `VideoSettings.subtitleOutputMode`: `external` only writes SRT/ASS and does not invoke FFmpeg; `mkvSoftAss` creates `output.mkv` with ASS soft subtitles; `mp4HardSubtitles` creates `output.mp4` with ASS burned in and requires an FFmpeg build with the `subtitles` filter. Treat translation output as untrusted text for subtitle formats: preserve visible text, but neutralize ASS override/control syntax before writing `.ass`.

## Translation Providers

Translation configuration is provider-specific. Keep base URL, model name, and API key scoped to the selected provider rather than sharing a single global endpoint. Supported provider labels are OpenAI-GPT, Anthropic-Claude, Google-Gemini, DeepSeek, Ollama, LM Studio, and OpenAI-compatible APIs. Store provider secrets in macOS Keychain accounts named `translation-api-key.<provider>`; never write them to settings JSON or `job.json`.

Subtitle translation should preserve the full script context. Do not automatically split remote API translation into parallel batches unless the user explicitly accepts the consistency tradeoff. DeepSeek requests should keep thinking disabled and use JSON object output to avoid slow reasoning responses while preserving structured parsing. Worker translation responses must preserve a one-to-one mapping for every expected segment ID; reject missing, extra, or duplicate IDs with clear errors before subtitle generation.

Keep translation prompt text as internal configuration rather than exposing it in the normal settings UI. API key controls should stay locked/read-only by default, reveal editing only after an explicit "编辑密钥" action, and treat saving an empty edited key as clearing the provider's stored Keychain entry.

## Build, Test, and Development Commands

- `swift build`: builds the macOS executable target.
- `swift test`: runs the Swift unit tests in `Tests/OtoChefAppTests`; if Command Line Tools cannot find XCTest, run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- In the Codex sandbox, use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache swift test --disable-sandbox` to avoid SwiftPM sandbox/cache failures.
- `script/build_and_run.sh`: builds, bundles, ad-hoc signs, and launches `dist/OtoChef.app`.
- `script/build_and_run.sh --verify`: launches the app and verifies the process starts.
- `script/setup_conda_env.sh`: creates or updates the `otochef` conda environment from `worker/environment.yml`.
- `cd worker && pytest`: runs Python worker tests when the `otochef` conda environment is activated.
- `cd worker && /opt/homebrew/bin/conda run -n otochef python -m pytest`: runs Python worker tests without relying on an activated shell environment.
- `cd worker && /opt/homebrew/bin/conda run -n otochef python -m otochef_worker ...`: runs the worker entry point directly when debugging pipeline behavior.

## Coding Style & Naming Conventions

Use 4-space indentation for Swift and Python. Swift types use `UpperCamelCase`; methods, properties, and local values use `lowerCamelCase`. Keep Swift domain and configuration type definitions in `Domain`, SwiftUI views in `Views`, state containers in `Stores`, and integration logic in `Services`. Python modules use lowercase snake_case filenames, and functions/variables use `snake_case`. Prefer small, focused services and tests that mirror the behavior being changed.

## Testing Guidelines

Add or update tests for behavior changes. Swift test files should follow the existing `FeatureTests.swift` pattern, such as `JobValidatorTests.swift`. Python tests should follow `test_feature.py`, such as `test_pipeline.py`. Run the relevant targeted suite during development and both `swift test` and `cd worker && pytest` before handing off cross-boundary changes.

## Commit & Pull Request Guidelines

Recent history uses concise imperative subjects, often Conventional Commit prefixes such as `feat:`, `fix:`, and `chore:`. Follow that style: `fix: harden worker pipeline` or `feat: add worker progress events`. Pull requests should describe the user-visible change, list Swift and Python tests run, link related issues or plans, and include screenshots or screen recordings for UI changes.

The public GitHub default branch is `main`.

## Public Documentation

`README.md` is the default English project overview, and `README.zh-CN.md` is the Simplified Chinese version linked from it. Keep both README files user-facing: setup, usage, and contributor checks are appropriate; agent instructions, internal implementation plans, and repository-maintenance warnings belong in AGENTS.md, CONTRIBUTING.md, or other developer docs instead.

## Security & Configuration Tips

Do not commit API keys, generated app bundles, build output, or local model/media files. Store secrets through the app settings/keychain flow rather than literals in source. Keychain saves should keep provider-specific accounts and explicit local accessibility; worker launches should pass only an allowlisted environment plus explicit worker overrides rather than inheriting the full parent process environment. Keep Python package dependencies in `worker/pyproject.toml` and environment-level tools such as FFmpeg in `worker/environment.yml`.
