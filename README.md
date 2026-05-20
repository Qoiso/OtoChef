# OtoChef

[English](README.md) | [中文](README.zh-CN.md)

OtoChef is a macOS subtitle pipeline for Japanese audio and video workflows. The app performs native WhisperKit/Core ML transcription, then hands the transcript to a Python worker for translation, subtitle rendering, and optional FFmpeg video output.

## Features

- Native macOS transcription with WhisperKit/Core ML.
- Project-local WhisperKit model storage under `Models/whisperkit`.
- Provider-specific translation settings for OpenAI, Anthropic, Gemini, DeepSeek, Ollama, LM Studio, and OpenAI-compatible APIs.
- API keys stored in macOS Keychain instead of settings JSON or job files.
- Subtitle output as external SRT/ASS, MKV with ASS soft subtitles, or MP4 with burned-in subtitles.
- A small Python worker for translation, subtitle rendering, progress events, and FFmpeg orchestration.

## Requirements

- macOS 14 or newer.
- Xcode or Xcode Command Line Tools with Swift 5.10 support.
- Conda for the Python worker environment.
- FFmpeg for MKV/MP4 video output. `ffmpeg-full` is recommended for MP4 hard subtitles because it includes the `subtitles` filter.
- WhisperKit/Core ML models downloaded separately.

## Model Setup

OtoChef reads WhisperKit models from the ignored project-root directory:

```text
Models/whisperkit
```

Download compatible Core ML models from [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml), then place them under that directory. Do not commit model files.

Current model choices are:

- `openai_whisper-large-v3` - quality-first full large-v3 model.
- `openai_whisper-large-v3_947MB` - balanced large-v3 compressed model, used by default.
- `large-v3-v20240930_626MB` - faster large-v3 turbo model.
- `tiny` - small model for smoke testing.

The first model load may compile Core ML artifacts. Later runs normally reuse the system cache.

## Translation Setup

Translation settings are scoped per provider. Base URL, model name, and API key are not shared across providers.

Supported provider labels:

- OpenAI-GPT
- Anthropic-Claude
- Google-Gemini
- DeepSeek
- Ollama
- LM Studio
- OpenAI-compatible APIs

Remote API keys are stored in macOS Keychain accounts named `translation-api-key.<provider>`. OtoChef does not write secrets to `settings.json` or `job.json`.

Local OpenAI-compatible endpoints such as Ollama and LM Studio can be used without an API key unless your local server requires one.

## Subtitle Output

Choose the output mode in Settings:

- External subtitles: writes SRT and ASS only, and does not invoke FFmpeg.
- MKV + ASS soft subtitles: creates `output.mkv` with ASS subtitles attached.
- MP4 hard subtitles: creates `output.mp4` with ASS subtitles burned in. This requires an FFmpeg build with the `subtitles` filter.

Translation text is treated as untrusted subtitle content. OtoChef preserves visible text while neutralizing ASS override/control syntax before writing `.ass`.

## Build And Run

Build the Swift app:

```sh
swift build
```

Create and update the Python worker environment:

```sh
script/setup_conda_env.sh
```

Build, bundle, sign, and launch the macOS app:

```sh
script/build_and_run.sh
```

Verify that the bundled app starts:

```sh
script/build_and_run.sh --verify
```

## Tests

Run Swift tests:

```sh
swift test
```

In the Codex sandbox or when SwiftPM cache permissions are noisy, use:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=$PWD/.build/module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.build/module-cache \
swift test --disable-sandbox
```

Run Python worker tests:

```sh
cd worker
/opt/homebrew/bin/conda run -n otochef python -m pytest
```

## Repository Layout

```text
Sources/OtoChefApp/        SwiftPM macOS app target
Tests/OtoChefAppTests/     Swift unit tests
worker/otochef_worker/     Python media worker package
worker/tests/              Python worker tests
Resources/                 App bundle resources
script/                    Setup, build, and run helpers
docs/superpowers/          Design notes and implementation plans
```

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a substantial change.

## Security

Please do not report security issues in public issues. See [SECURITY.md](SECURITY.md) for the disclosure process.

## License

OtoChef is available under the [MIT License](LICENSE).
