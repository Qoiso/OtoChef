# OtoChef Design Spec

Date: 2026-05-17

## Goal

OtoChef is a native macOS utility for making a Chinese-subtitled video from one Japanese audio file and one still image. The first version takes:

- a Japanese audio file,
- a still image,
- an output folder,
- user-configured ASR, translation, and FFmpeg settings,

and produces:

- an MP4 video that uses the still image as the visual track,
- the original Japanese audio as the audio track,
- burned-in Chinese subtitles,
- editable subtitle files beside the video.

The MVP does not generate new audio. It does not include TTS, voice cloning, dubbing, batch processing, or a subtitle timeline editor.

## Architecture

The app uses a native SwiftUI shell with an isolated Python media worker:

- SwiftUI macOS app: file selection, output selection, settings, progress display, logs, diagnostics, and output links.
- Conda Python worker: job validation, ASR, translation orchestration, subtitle generation, and FFmpeg command execution.
- FFmpeg: static-image video generation, audio muxing or encoding, ASS subtitle burn-in, and MP4 output.

Swift starts the worker with a `job.json` file. The worker streams JSONL progress events back to Swift so the UI can update without parsing unstructured logs.

## Dependency Isolation

Python dependencies are managed only through a project-specific conda environment. The app and scripts must not install Python packages into system Python or unrelated user environments.

The project provides:

- `environment.yml` for the `otochef` conda environment,
- a setup script for creating or updating that environment,
- a worker entrypoint run through `conda run -n otochef ...`,
- preflight checks that verify the configured conda executable, environment, imports, model path, translator settings, output folder, and FFmpeg executable.

## ASR Design

The MVP implements one ASR provider: `FasterWhisperASRProvider`.

Recommended model:

- `Systran/faster-whisper-large-v3`
- Download page: <https://huggingface.co/Systran/faster-whisper-large-v3>

The setting accepts any value `faster-whisper` can load:

- a local model directory,
- a Hugging Face repository ID such as `Systran/faster-whisper-large-v3`,
- an internal model name such as `large-v3`.

The worker owns an `ASRProvider` interface so future providers can be added without changing the UI flow, subtitle generation, or FFmpeg stage. Possible future providers include WhisperX, whisper.cpp, local ASR servers, or cloud ASR APIs, but they are out of scope for the first version.

The app should expose practical faster-whisper options:

- device: `auto`, `cpu`, or `cuda`,
- compute type: `auto`, `int8`, `float16`, or another supported explicit value,
- language default: Japanese,
- optional VAD toggle,
- optional beam size.

## Translation Design

Translation supports two backends in the first version:

- Local endpoint,
- OpenAI-compatible API endpoint.

Both backends share the same translation contract: Japanese segments in, Chinese segments out, preserving segment IDs and timing from ASR.

Settings include:

- backend type,
- base URL or local endpoint URL,
- model name,
- prompt template,
- timeout and retry limits,
- API key for API mode.

API keys are stored in the macOS Keychain, not in plain settings files.

The translator may batch segments to reduce overhead, but it must keep output mapped to the original segment IDs. On translation failure, the worker should preserve the ASR transcript and report which translation batch failed.

## Processing Pipeline

Each job has a working folder containing reproducible intermediate artifacts.

Pipeline:

1. Validate inputs and configuration.
2. Run ASR and write `transcript.ja.json`.
3. Translate segments and write `translation.zh.json`.
4. Generate `subtitles.zh.srt` and `subtitles.zh.ass`.
5. Run FFmpeg to create the final MP4 with burned-in subtitles.
6. Return artifact paths and a completion report to the UI.

Artifacts:

- `job.json`: selected files, output folder, ASR settings, translation settings, subtitle style, and video settings.
- `transcript.ja.json`: ASR output with segment IDs, start times, end times, and Japanese text.
- `translation.zh.json`: Chinese text mapped to original segment IDs.
- `subtitles.zh.srt`: editable subtitle file.
- `subtitles.zh.ass`: styled subtitle file used for burn-in.
- `output.mp4`: final video.

JSONL worker events include:

- `job_started`,
- `stage_started`,
- `progress`,
- `warning`,
- `artifact_created`,
- `stage_failed`,
- `job_finished`.

## Video And Subtitle Output

Default video behavior:

- resolution: `1920x1080`,
- image fit mode: `contain`,
- background fill: black,
- audio: preserve original audio when MP4-compatible; otherwise encode to AAC,
- subtitle burn-in: use ASS subtitles.

Subtitle behavior:

- timestamps come from ASR segments,
- long Chinese lines are wrapped before ASS generation,
- default placement is bottom center,
- default style should be legible over varied images,
- SRT and ASS files are always saved next to the final video.

## UI Design

The first version is a compact macOS utility window, not a marketing-style landing page.

Primary main-window controls:

- choose audio,
- choose image,
- choose output folder,
- start processing,
- current stage,
- progress bar,
- warning and log tail,
- output artifact links.

Sidebar sections:

- New Job,
- Recent Jobs,
- Settings,
- Diagnostics.

Settings sections:

- ASR,
- Translation,
- Tools,
- Output Defaults.

The Settings view includes model recommendation text for `Systran/faster-whisper-large-v3` and the Hugging Face link. Diagnostics can run preflight checks without starting a full job.

## Error Handling

Preflight errors block the Start button and show specific remediation:

- missing conda executable,
- missing `otochef` environment,
- missing Python dependency,
- invalid ASR model path or model ID,
- invalid translator config,
- missing FFmpeg,
- unwritable output folder.

Runtime errors include:

- failed stage name,
- concise command or operation summary,
- relevant log excerpt,
- retained artifact paths.

Partial artifacts remain in the working folder for debugging and reuse.

## Testing Strategy

Swift tests:

- settings encoding and decoding,
- job validation,
- JSONL event parsing,
- progress state transitions.

Python tests:

- ASR provider contract with mocked faster-whisper output,
- translation batching and ID preservation,
- SRT timestamp formatting,
- ASS escaping and line wrapping,
- FFmpeg command generation.

Integration smoke test:

- tiny Japanese audio fixture,
- small still-image fixture,
- mocked or lightweight translation backend,
- full worker pipeline through subtitle and FFmpeg output.

Build and run:

- use a project-local `script/build_and_run.sh`,
- add `.codex/environments/environment.toml` so the Codex Run button can launch the macOS app.

## References

- Systran faster-whisper large-v3 model card: <https://huggingface.co/Systran/faster-whisper-large-v3>
- SYSTRAN faster-whisper README: <https://github.com/SYSTRAN/faster-whisper>
