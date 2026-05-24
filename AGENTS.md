# Repository Guidelines

## Project Structure & Module Organization

OtoChef is a SwiftPM macOS app with a Python media worker. The app target lives in `Sources/OtoChefApp`, organized by `App`, `Domain`, `Views`, `Stores`, and `Services`. `Sources/OtoChefApp/Domain` contains Swift domain and configuration type definitions such as app settings and job records; it is not a directory for Whisper/WhisperKit model files. Swift tests live in `Tests/OtoChefAppTests`. The Python worker package is in `worker/otochef_worker`, with pytest tests in `worker/tests`. App bundle resources live in `Resources`; `script/build_and_run.sh` copies expected bundle resources such as `Resources/AppIcon.icns` and `Resources/EmbossedDetailBackground.png` into `dist/OtoChef.app`. For small app-bundle resources, keep using this script-level copy strategy unless intentionally migrating SwiftPM resource handling for the whole target. Setup and run helpers are in `script/`. Design notes and implementation plans are under `docs/superpowers/`. Keep sample media and local test inputs out of app or worker source directories; local media scratch directories such as `测试内容/` and `local-media/` are ignored and must stay out of Git.

## ASR, Models, and Video Output

ASR is native Swift using WhisperKit/Core ML from `argmaxinc/argmax-oss-swift`; do not add new faster-whisper dependencies or route normal macOS transcription through Python. The Swift app writes the internal `transcript.ja.json`, and the Python worker continues only as far as the selected outputs require. The Python worker no longer has a faster-whisper fallback; if `transcript.ja.json` is missing, the worker should fail clearly and tell the user to run the native ASR step first. Local WhisperKit/Core ML model files live under the ignored project-root directory `Models/whisperkit`; keep downloaded model files out of Git. Current expected model names are `openai_whisper-large-v3`, `openai_whisper-large-v3_947MB`, `large-v3-v20240930_626MB`, and `tiny`.

WhisperKit model choices are user-facing quality tiers in `ASRSettings.whisperKitModelChoices`; keep labels, defaults, and tests aligned when changing them. Keep VAD strategy uniform across model tiers. WhisperKit concurrent chunk processing is capped by `ASRSettings.maxWhisperKitConcurrentSegments`; keep the UI stepper, default settings, persisted-settings migration, and `WhisperKitTranscriptionService.effectiveConcurrentWorkerCount` in sync. If parallel WhisperKit output has suspicious leading gaps or large timing gaps, the native service should retry sequentially rather than special-casing one model tier.

`WhisperKitTranscriptionService` may cache a loaded WhisperKit model to avoid reloading between consecutive queued jobs, but `JobStore` must release native transcription resources once all running and queued jobs are finished. Keep `NativeTranscriptionService.releaseResources()` and the job-id lifecycle tests in sync when changing ASR ownership or queue completion behavior.

Output artifacts are user-selected through `VideoSettings.outputFiles`; keep the settings UI, validation, Swift job JSON, Python model parsing, and worker pipeline in sync. Supported outputs are video, Japanese subtitles, Chinese subtitles, and bilingual subtitles, and at least one must be selected. Only require an image and FFmpeg when video is selected; only require translation settings and API keys when Chinese, bilingual, or video output is selected. Use `VideoSettings.subtitleOutputMode` only for selected video output: `mkvSoftAss` creates `output.mkv` with ASS soft subtitles, while `mp4HardSubtitles` creates `output.mp4` with ASS burned in and requires an FFmpeg build with the `subtitles` filter. User-visible artifacts should be written directly into the selected output directory, defaulting to project-root `output/`; internal files such as `job.json`, `transcript.ja.json`, and `translation.zh.json` belong under the hidden working directory `output/.otochef/<job-id>/`. Treat translation output as untrusted text for subtitle formats: preserve visible text, but neutralize ASS override/control syntax before writing `.ass`.

## Translation Providers

Translation configuration is provider-specific. Keep base URL, model name, and API key scoped to the selected provider rather than sharing a single global endpoint. Supported provider labels are OpenAI-GPT, Anthropic-Claude, Google-Gemini, DeepSeek, Ollama, LM Studio, and OpenAI-compatible APIs. Store provider secrets in macOS Keychain accounts named `translation-api-key.<provider>`; never write them to settings JSON or `job.json`.

Subtitle translation should preserve the full script context. Do not automatically split remote API translation into parallel batches unless the user explicitly accepts the consistency tradeoff. DeepSeek requests should keep thinking disabled and use JSON object output to avoid slow reasoning responses while preserving structured parsing. Worker translation responses must preserve a one-to-one mapping for every expected segment ID; reject missing, extra, or duplicate IDs with clear errors before subtitle generation.

Keep translation prompt text as internal configuration rather than exposing it in the normal settings UI. API key controls should stay locked/read-only by default with only a masked saved-value placeholder; reveal editing only after an explicit "编辑密钥" action, preload and visibly display the provider's existing Keychain key in the edit field, and treat saving an empty edited key as clearing the provider's stored Keychain entry. Treat provider request errors as secret-bearing: redact API keys and token-like URL query parameters before emitting worker events, persisting recent-job status, or surfacing errors in the UI.

## Job Execution, Queueing, and Diagnostics

Job submission supports both parallel and queued modes through `JobSubmissionMode`. Do not treat `JobStore.isRunning` as a global submission gate: users may add another parallel job while one is running, or enqueue jobs that start automatically after the jobs blocking them finish. Keep worker events associated with the correct job ID, keep recent-job progress/status per job, and keep `PythonWorkerClient` able to retain multiple concurrent `Process` instances safely until each terminates.

The New Task page owns user-input validation feedback; failed starts should surface validation messages in the task log without creating a recent-job record or mutating any active job. After a successful submission, clear the draft audio/image inputs but preserve the output directory so users can quickly submit more parallel or queued jobs. The New Task queue shows only active running work; the Recent Tasks page is for completed jobs only, with clear/open actions scoped to those completed rows.

Keep the New Task log user-facing: show time, behavior, and percentages, but avoid internal stage prefixes and low-level event strings. The dedicated Logs page is the developer/support log surface and should show only the latest run's complete details. Persist that full log to `output/.otochef/latest-run.log` under the selected output directory, overwriting it on each new dispatched job rather than accumulating unbounded logs.

The Diagnostics page is for manual software-environment checks such as Conda, FFmpeg, model paths, and worker directories. Do not run diagnostics automatically on app launch, and do not use the Diagnostics page for draft input errors. Preserve native macOS settings UI conventions such as grouped `Form` styling unless the user explicitly asks for a broader redesign. Keep `EmbossedBackgroundView` scoped to the `NavigationSplitView` detail pane only; the sidebar should retain the native macOS source-list/material appearance. Detail content cards should stay restrained: 8px corner radius, system material, and light shadows.

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

## Git Workflow & Pull Requests

The public GitHub default branch is `main`. This repository is currently mostly single-maintainer, so do not force a pull-request workflow for every local change. Match the Git workflow to the user's request:

- For normal coding or documentation edits, inspect `git status -sb` and the relevant diff, then leave changes unstaged and uncommitted unless the user asks for a commit or handoff.
- When committing, stage only the intended files. Prefer explicit path staging; use `git add -p` when a file contains mixed user and agent changes. Never stage unrelated local work.
- Use concise imperative commit subjects, usually with Conventional Commit prefixes such as `feat:`, `fix:`, `docs:`, `test:`, or `chore:`. Add a body only when the rationale, risk, migration note, or security context is not obvious.
- Keep commits atomic and reviewable: one logical change per commit, with tests or docs in the same commit when they prove or explain that change. Amend unpublished local commits instead of creating noisy follow-up commits.
- For this repository's usual full GitHub handoff, commit directly on `main` and push to `origin/main` unless the user asks for a branch or pull request. Use a short-lived `codex/<description>` branch for PR-based or explicitly isolated work.

### Validation Before Handoff

Before committing, pushing, or handing off finished work, run `git diff --check` plus the relevant local validation:

- Swift-only changes: run the documented Swift test command.
- Worker-only changes: run the documented Python worker test command.
- Cross-boundary changes: run both Swift and Python tests.
- UI-visible app changes: run the relevant tests and use `script/build_and_run.sh --verify` when practical.
- Docs-only changes: `git diff --check` is sufficient unless the docs describe executable behavior.

### Publishing To GitHub

Use the Codex GitHub plugin publish workflow only when the user explicitly asks for GitHub publication, such as push, publish, open a PR, merge, or otherwise "finish the Git work." A local commit-only request should stop after the local commit unless the user asks for a broader handoff. For this single-maintainer repository, publication defaults to direct `main` delivery without a PR unless the user explicitly requests a branch or pull request. In publication mode:

- Use local `git` for branch creation, staging, commits, and pushes.
- Prefer the GitHub app/plugin for PR creation only when a PR is requested and the branch is pushed.
- Use `gh` where the plugin expects it: authentication checks, current-branch PR discovery, fallback PR creation, and GitHub Actions checks or logs.
- When a PR is requested, open it as a draft by default unless the user asks for a ready-for-review PR. Pull requests should include a user-visible summary, tests run, related issues or plans when relevant, and screenshots or recordings for UI changes.

GitHub Actions runs `Swift tests` and `Python worker tests` on pull requests and on pushes to `main`. When GitHub access is available and the user requested a publish, merge, or complete GitHub handoff, verify the latest CI run for the pushed commit before calling the Git work complete. If CI is pending, wait; if it fails, report the failing job and either fix it or ask for direction. If CI cannot be checked, state the exact blocker.

Merge back to `main` only when the user explicitly asks. Prefer fast-forward merges, rerun the relevant local checks on merged `main`, then push the requested final branch. After a successful local merge, delete only the local topic branch that was fully merged. Never force-push, delete remote branches, rewrite published history, or discard work without explicit user approval.

Final handoff for local-only work should state the changed files and validation results. Final handoff for published work should also state the commit SHA, branch pushed, PR URL if created, GitHub Actions result, and whether local `main` is synced with `origin/main`.

## Public Documentation

`README.md` is the default English project overview, and `README.zh-CN.md` is the Simplified Chinese version linked from it. Keep both README files user-facing: setup, usage, and contributor checks are appropriate; agent instructions, internal implementation plans, and repository-maintenance warnings belong in AGENTS.md, CONTRIBUTING.md, or other developer docs instead.

## Security & Configuration Tips

Do not commit API keys, generated app bundles, build output, or local model/media files. Store secrets through the app settings/keychain flow rather than literals in source. Keychain saves should keep provider-specific accounts and explicit local accessibility; worker launches should pass only an allowlisted environment plus explicit worker overrides rather than inheriting the full parent process environment. Keep Python package dependencies in `worker/pyproject.toml` and environment-level tools such as FFmpeg in `worker/environment.yml`.
