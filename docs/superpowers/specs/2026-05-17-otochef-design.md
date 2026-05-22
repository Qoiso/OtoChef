# OtoChef Design Spec

Date: 2026-05-17

## Goal

OtoChef is a native macOS utility for making subtitles and optional videos from Japanese audio. The current app takes:

- a Japanese audio file,
- an optional still image when video output is selected,
- an output folder,
- user-configured ASR, translation, and FFmpeg settings,

and produces:

- selected subtitle files: Japanese, Chinese, bilingual, or any combination,
- optionally, a static-image video using the original Japanese audio,
- either an MKV with ASS soft subtitles or an MP4 with burned-in subtitles when video output is selected.

The MVP does not generate new audio. It does not include TTS, voice cloning, dubbing, batch media import, or a subtitle timeline editor.

## Architecture

The app uses a native SwiftUI shell with an isolated Python media worker:

- SwiftUI macOS app: file selection, output selection, settings, progress display, logs, diagnostics, and output links.
- Native Swift ASR: WhisperKit/Core ML transcription writes `transcript.ja.json` before the worker starts.
- Conda Python worker: translation orchestration, subtitle generation, and optional FFmpeg command execution.
- FFmpeg: optional static-image video generation, audio encoding, ASS soft subtitle muxing, or ASS subtitle burn-in.

Swift starts the worker with a `job.json` file. The worker streams JSONL progress events back to Swift so the UI can update without parsing unstructured logs.

## Dependency Isolation

Python dependencies are managed only through a project-specific conda environment. The app and scripts must not install Python packages into system Python or unrelated user environments.

The project provides:

- `environment.yml` for the `otochef` conda environment,
- a setup script for creating or updating that environment,
- a worker entrypoint run through `conda run -n otochef ...`,
- manual diagnostics that check the configured conda executable, environment name, FFmpeg path, model folder, selected model folder, and worker directory.

## ASR Design

The current ASR path is native Swift using WhisperKit/Core ML from `argmaxinc/argmax-oss-swift`. Normal macOS transcription does not route through Python. Swift writes `transcript.ja.json`, then the Python worker consumes that transcript for translation and subtitle/video output.

Current project-local model choices:

- `openai_whisper-large-v3`
- `openai_whisper-large-v3_947MB`
- `large-v3-v20240930_626MB`
- `tiny`

Models live under the ignored project-root directory `Models/whisperkit`. The Settings UI exposes user-facing quality tiers from `ASRSettings.whisperKitModelChoices`; keep labels, defaults, migration, and tests aligned when changing them.

The app exposes Japanese language defaults, VAD, and a capped WhisperKit concurrent segment count. If parallel WhisperKit output has suspicious leading gaps or large timing gaps, the native service retries sequentially.

## Translation Design

Translation supports provider-specific remote or local API-compatible providers:

- OpenAI-GPT,
- Anthropic-Claude,
- Google-Gemini,
- DeepSeek,
- Ollama,
- LM Studio,
- OpenAI-compatible APIs.

Both backends share the same translation contract: Japanese segments in, Chinese segments out, preserving segment IDs and timing from ASR.

Settings include:

- provider,
- provider-scoped base URL,
- model name,
- prompt template,
- timeout and retry limits,
- API key when required or optionally accepted by the selected provider.

API keys are stored in the macOS Keychain, not in plain settings files.

Subtitle translation preserves full-script context in one request unless the user explicitly accepts the consistency tradeoff of splitting work. The worker validates that the provider returns every expected segment ID before generating subtitle files.

## Processing Pipeline

Each job has a working folder containing reproducible intermediate artifacts.

Pipeline:

1. Validate inputs and configuration.
2. Run native WhisperKit ASR and write `transcript.ja.json`.
3. Launch the worker. Translate segments and write `translation.zh.json` only when the selected outputs require Chinese text.
4. Generate the selected visible subtitle files: Japanese, Chinese, and/or bilingual SRT/ASS.
5. If video output is selected, create `output.mkv` with ASS soft subtitles or `output.mp4` with burned-in ASS subtitles, depending on `subtitleOutputMode`.
6. Return artifact paths and a completion report to the UI.

Artifacts:

- `output/.otochef/<job-id>/job.json`: selected files, output folder, ASR settings, translation settings, subtitle style, and video settings.
- `output/.otochef/<job-id>/transcript.ja.json`: ASR output with segment IDs, start times, end times, and Japanese text.
- `output/.otochef/<job-id>/translation.zh.json`: Chinese text mapped to original segment IDs when translation is needed.
- `subtitles.ja.srt` and `subtitles.ja.ass`: optional Japanese subtitle files.
- `subtitles.zh.srt` and `subtitles.zh.ass`: optional Chinese subtitle files.
- `subtitles.ja-zh.srt` and `subtitles.ja-zh.ass`: optional bilingual subtitle files.
- `output.mkv` or `output.mp4`: optional final video, depending on subtitle output mode.
- `output/.otochef/latest-run.log`: latest complete developer/support log for the selected output directory.

JSONL worker events include:

- `job_started`,
- `stage_started`,
- `progress`,
- `warning`,
- `artifact_created`,
- `stage_failed`,
- `job_finished`.

## Video And Subtitle Output

Default subtitle/video behavior:

- resolution: `1920x1080`,
- image fit mode: `contain`,
- background fill: black,
- selected output files default to Chinese subtitles,
- video output is optional and is the only mode that requires an image and FFmpeg,
- video subtitle mode supports MKV + ASS soft subtitles or MP4 hard subtitles when FFmpeg supports the `subtitles` filter.

Subtitle behavior:

- timestamps come from ASR segments,
- long Chinese lines are wrapped before ASS generation,
- default placement is bottom center,
- default style should be legible over varied images,
- visible SRT, ASS, MKV, and MP4 artifacts are saved directly in the selected output directory.

## UI Design

The first version is a compact macOS utility window, not a marketing-style landing page.

Primary main-window controls:

- choose audio,
- choose image,
- choose output folder,
- start processing in queued or parallel mode,
- active queue/progress rows,
- warning and log tail,
- output artifact links.

Sidebar sections:

- New Job,
- Recent Jobs,
- Settings,
- Diagnostics,
- Logs.

Settings sections:

- ASR,
- Translation,
- Tools,
- Output Defaults.

The Settings view includes WhisperKit model guidance and a project-local model folder note. Diagnostics can run preflight checks without starting a full job.

## Error Handling

Draft validation errors are shown in the New Task log without creating a recent-job record:

- missing conda executable,
- missing `otochef` environment,
- invalid ASR model path or model ID,
- invalid translator config,
- missing FFmpeg when video output is selected,
- missing output folder,
- missing audio, or missing image when video output is selected.

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

- native transcript contract and worker behavior when a transcript is already present,
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

- WhisperKit Core ML models: <https://huggingface.co/argmaxinc/whisperkit-coreml>
- argmax OSS Swift / WhisperKit: <https://github.com/argmaxinc/argmax-oss-swift>
