# OtoChef Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the OtoChef macOS MVP: a SwiftUI app that launches an isolated conda Python worker to transcribe Japanese audio, translate to Chinese, generate subtitles, and create a still-image MP4 with burned-in subtitles.

**Architecture:** Use SwiftPM for the native macOS app and unit tests. Keep Python media work in `worker/` with pytest coverage and a conda `environment.yml`. Swift and Python communicate through a `job.json` file and JSONL worker events.

**Tech Stack:** Swift 5.10+, SwiftUI, Foundation process APIs, XCTest, Python 3.11, conda, faster-whisper, requests, pytest, FFmpeg.

---

## File Structure

Create this structure:

```text
Package.swift
Sources/OtoChefApp/App/OtoChefApp.swift
Sources/OtoChefApp/Models/JobModels.swift
Sources/OtoChefApp/Models/AppSettings.swift
Sources/OtoChefApp/Services/JobValidator.swift
Sources/OtoChefApp/Services/WorkerEventParser.swift
Sources/OtoChefApp/Services/JobFileWriter.swift
Sources/OtoChefApp/Services/APIKeyStore.swift
Sources/OtoChefApp/Services/PythonWorkerClient.swift
Sources/OtoChefApp/Stores/JobStore.swift
Sources/OtoChefApp/Views/ContentView.swift
Sources/OtoChefApp/Views/NewJobView.swift
Sources/OtoChefApp/Views/SettingsView.swift
Sources/OtoChefApp/Views/DiagnosticsView.swift
Tests/OtoChefAppTests/JobValidatorTests.swift
Tests/OtoChefAppTests/WorkerEventParserTests.swift
Tests/OtoChefAppTests/AppSettingsTests.swift
Tests/OtoChefAppTests/APIKeyStoreTests.swift
worker/pyproject.toml
worker/environment.yml
worker/otochef_worker/__init__.py
worker/otochef_worker/__main__.py
worker/otochef_worker/models.py
worker/otochef_worker/events.py
worker/otochef_worker/asr.py
worker/otochef_worker/translation.py
worker/otochef_worker/subtitles.py
worker/otochef_worker/ffmpeg.py
worker/otochef_worker/pipeline.py
worker/tests/test_models.py
worker/tests/test_events.py
worker/tests/test_subtitles.py
worker/tests/test_translation.py
worker/tests/test_ffmpeg.py
worker/tests/test_pipeline.py
script/build_and_run.sh
script/setup_conda_env.sh
.codex/environments/environment.toml
```

Responsibility boundaries:

- Swift `Models/`: codable job settings and app state types only.
- Swift `Services/`: validation, event parsing, and worker process launch only.
- Swift `JobFileWriter`: job working-folder creation and `job.json` encoding only.
- Swift `APIKeyStore`: Keychain-backed secret storage and in-memory test double.
- Swift `Stores/`: observable UI state and job orchestration only.
- Swift `Views/`: layout and user interaction only.
- Python `models.py`: job and artifact dataclasses.
- Python `events.py`: JSONL event construction.
- Python `asr.py`: `ASRProvider` contract and faster-whisper implementation.
- Python `translation.py`: OpenAI-compatible translation implementation usable for local or remote endpoints.
- Python `subtitles.py`: SRT and ASS rendering.
- Python `ffmpeg.py`: FFmpeg command construction and execution.
- Python `pipeline.py`: stage orchestration and artifact writing.

---

### Task 1: SwiftPM App Bootstrap

**Files:**
- Create: `Package.swift`
- Create: `Sources/OtoChefApp/App/OtoChefApp.swift`
- Create: `Sources/OtoChefApp/Views/ContentView.swift`
- Create: `Tests/OtoChefAppTests/AppSettingsTests.swift`

- [ ] **Step 1: Write a basic Swift settings test**

Create `Tests/OtoChefAppTests/AppSettingsTests.swift`:

```swift
import XCTest
@testable import OtoChefApp

final class AppSettingsTests: XCTestCase {
    func testDefaultSettingsUseFasterWhisperAndSystranLargeV3() throws {
        let settings = AppSettings.defaults

        XCTAssertEqual(settings.asr.backend, .fasterWhisper)
        XCTAssertEqual(settings.asr.model, "Systran/faster-whisper-large-v3")
        XCTAssertEqual(settings.conda.environmentName, "otochef")
        XCTAssertEqual(settings.video.width, 1920)
        XCTAssertEqual(settings.video.height, 1080)
    }
}
```

- [ ] **Step 2: Create `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OtoChef",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OtoChef", targets: ["OtoChefApp"])
    ],
    targets: [
        .executableTarget(
            name: "OtoChefApp",
            path: "Sources/OtoChefApp"
        ),
        .testTarget(
            name: "OtoChefAppTests",
            dependencies: ["OtoChefApp"],
            path: "Tests/OtoChefAppTests"
        )
    ]
)
```

- [ ] **Step 3: Add app entrypoint**

Create `Sources/OtoChefApp/App/OtoChefApp.swift`:

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct OtoChefApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("OtoChef") {
            ContentView()
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
```

- [ ] **Step 4: Add temporary root view**

Create `Sources/OtoChefApp/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OtoChef")
                .font(.largeTitle)
            Text("Japanese audio, Chinese subtitles, still-image video.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
```

- [ ] **Step 5: Add the settings model used by the test**

Create `Sources/OtoChefApp/Models/AppSettings.swift`:

```swift
import Foundation

struct AppSettings: Codable, Equatable {
    var asr: ASRSettings
    var translation: TranslationSettings
    var conda: CondaSettings
    var tools: ToolSettings
    var video: VideoSettings

    static let defaults = AppSettings(
        asr: ASRSettings(
            backend: .fasterWhisper,
            model: "Systran/faster-whisper-large-v3",
            device: "auto",
            computeType: "auto",
            language: "ja",
            vadEnabled: true,
            beamSize: 5
        ),
        translation: TranslationSettings(
            backend: .api,
            endpoint: "http://localhost:11434/v1",
            model: "qwen2.5:7b",
            prompt: "Translate each Japanese subtitle segment into natural Simplified Chinese. Preserve IDs.",
            timeoutSeconds: 120,
            retryLimit: 2
        ),
        conda: CondaSettings(executablePath: "/opt/homebrew/bin/conda", environmentName: "otochef"),
        tools: ToolSettings(ffmpegPath: "/opt/homebrew/bin/ffmpeg"),
        video: VideoSettings(width: 1920, height: 1080, imageFit: .contain, backgroundColor: "black")
    )
}

enum ASRBackend: String, Codable, Equatable {
    case fasterWhisper
}

struct ASRSettings: Codable, Equatable {
    var backend: ASRBackend
    var model: String
    var device: String
    var computeType: String
    var language: String
    var vadEnabled: Bool
    var beamSize: Int
}

enum TranslationBackend: String, Codable, Equatable {
    case local
    case api
}

struct TranslationSettings: Codable, Equatable {
    var backend: TranslationBackend
    var endpoint: String
    var model: String
    var prompt: String
    var timeoutSeconds: Int
    var retryLimit: Int
}

struct CondaSettings: Codable, Equatable {
    var executablePath: String
    var environmentName: String
}

struct ToolSettings: Codable, Equatable {
    var ffmpegPath: String
}

enum ImageFit: String, Codable, Equatable {
    case contain
    case cover
}

struct VideoSettings: Codable, Equatable {
    var width: Int
    var height: Int
    var imageFit: ImageFit
    var backgroundColor: String
}
```

- [ ] **Step 6: Run the Swift test**

Run: `swift test --filter AppSettingsTests`

Expected: test passes.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: bootstrap SwiftPM macOS app"
```

---

### Task 2: Swift Job Models And Validation

**Files:**
- Create: `Sources/OtoChefApp/Models/JobModels.swift`
- Create: `Sources/OtoChefApp/Services/JobValidator.swift`
- Create: `Tests/OtoChefAppTests/JobValidatorTests.swift`

- [ ] **Step 1: Write failing validation tests**

Create `Tests/OtoChefAppTests/JobValidatorTests.swift`:

```swift
import XCTest
@testable import OtoChefApp

final class JobValidatorTests: XCTestCase {
    func testValidationFailsWhenAudioIsMissing() {
        let draft = JobDraft(
            audioURL: nil,
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: .defaults
        )

        let errors = JobValidator().validate(draft)

        XCTAssertEqual(errors, [.missingAudio])
    }

    func testValidationFailsWhenTranslationEndpointIsEmpty() {
        var settings = AppSettings.defaults
        settings.translation.endpoint = ""
        let draft = JobDraft(
            audioURL: URL(fileURLWithPath: "/tmp/audio.wav"),
            imageURL: URL(fileURLWithPath: "/tmp/image.png"),
            outputDirectory: URL(fileURLWithPath: "/tmp/out"),
            settings: settings
        )

        let errors = JobValidator().validate(draft)

        XCTAssertTrue(errors.contains(.missingTranslationEndpoint))
    }
}
```

- [ ] **Step 2: Implement job models**

Create `Sources/OtoChefApp/Models/JobModels.swift`:

```swift
import Foundation

struct JobDraft: Equatable {
    var audioURL: URL?
    var imageURL: URL?
    var outputDirectory: URL?
    var settings: AppSettings
}

struct OtoChefJob: Codable, Equatable {
    var id: UUID
    var audioPath: String
    var imagePath: String
    var outputDirectory: String
    var settings: AppSettings
    var createdAt: Date
}

enum JobValidationError: String, Equatable, Identifiable {
    case missingAudio
    case missingImage
    case missingOutputDirectory
    case missingASRModel
    case missingCondaExecutable
    case missingCondaEnvironment
    case missingFFmpeg
    case missingTranslationEndpoint
    case missingTranslationModel

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingAudio:
            return "请选择日语音频文件。"
        case .missingImage:
            return "请选择静态图片。"
        case .missingOutputDirectory:
            return "请选择输出文件夹。"
        case .missingASRModel:
            return "请填写 faster-whisper 模型路径或模型 ID。"
        case .missingCondaExecutable:
            return "请配置 conda 可执行文件路径。"
        case .missingCondaEnvironment:
            return "请配置 conda 环境名。"
        case .missingFFmpeg:
            return "请配置 FFmpeg 可执行文件路径。"
        case .missingTranslationEndpoint:
            return "请配置翻译服务地址。"
        case .missingTranslationModel:
            return "请配置翻译模型名称。"
        }
    }
}
```

- [ ] **Step 3: Implement validator**

Create `Sources/OtoChefApp/Services/JobValidator.swift`:

```swift
import Foundation

struct JobValidator {
    func validate(_ draft: JobDraft) -> [JobValidationError] {
        var errors: [JobValidationError] = []

        if draft.audioURL == nil {
            errors.append(.missingAudio)
        }
        if draft.imageURL == nil {
            errors.append(.missingImage)
        }
        if draft.outputDirectory == nil {
            errors.append(.missingOutputDirectory)
        }
        if draft.settings.asr.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingASRModel)
        }
        if draft.settings.conda.executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingCondaExecutable)
        }
        if draft.settings.conda.environmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingCondaEnvironment)
        }
        if draft.settings.tools.ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingFFmpeg)
        }
        if draft.settings.translation.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationEndpoint)
        }
        if draft.settings.translation.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingTranslationModel)
        }

        return errors
    }

    func makeJob(from draft: JobDraft, now: Date = Date()) throws -> OtoChefJob {
        let errors = validate(draft)
        if let first = errors.first {
            throw first
        }

        return OtoChefJob(
            id: UUID(),
            audioPath: draft.audioURL!.path,
            imagePath: draft.imageURL!.path,
            outputDirectory: draft.outputDirectory!.path,
            settings: draft.settings,
            createdAt: now
        )
    }
}

extension JobValidationError: Error { }
```

- [ ] **Step 4: Run validation tests**

Run: `swift test --filter JobValidatorTests`

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/OtoChefApp/Models/JobModels.swift Sources/OtoChefApp/Services/JobValidator.swift Tests/OtoChefAppTests/JobValidatorTests.swift
git commit -m "feat: add Swift job validation"
```

---

### Task 3: Swift Worker Event Parser

**Files:**
- Create: `Sources/OtoChefApp/Services/WorkerEventParser.swift`
- Create: `Tests/OtoChefAppTests/WorkerEventParserTests.swift`

- [ ] **Step 1: Write failing event parser tests**

Create `Tests/OtoChefAppTests/WorkerEventParserTests.swift`:

```swift
import XCTest
@testable import OtoChefApp

final class WorkerEventParserTests: XCTestCase {
    func testParsesStageStartedEvent() throws {
        let line = #"{"type":"stage_started","stage":"asr","message":"Transcribing audio"}"#

        let event = try WorkerEventParser().parse(line)

        XCTAssertEqual(event.type, .stageStarted)
        XCTAssertEqual(event.stage, "asr")
        XCTAssertEqual(event.message, "Transcribing audio")
    }

    func testParsesArtifactEvent() throws {
        let line = #"{"type":"artifact_created","stage":"subtitle","path":"/tmp/subtitles.zh.ass"}"#

        let event = try WorkerEventParser().parse(line)

        XCTAssertEqual(event.type, .artifactCreated)
        XCTAssertEqual(event.path, "/tmp/subtitles.zh.ass")
    }
}
```

- [ ] **Step 2: Implement parser**

Create `Sources/OtoChefApp/Services/WorkerEventParser.swift`:

```swift
import Foundation

enum WorkerEventType: String, Codable, Equatable {
    case jobStarted = "job_started"
    case stageStarted = "stage_started"
    case progress
    case warning
    case artifactCreated = "artifact_created"
    case stageFailed = "stage_failed"
    case jobFinished = "job_finished"
}

struct WorkerEvent: Codable, Equatable, Identifiable {
    var id = UUID()
    var type: WorkerEventType
    var stage: String?
    var message: String?
    var progress: Double?
    var path: String?

    enum CodingKeys: String, CodingKey {
        case type
        case stage
        case message
        case progress
        case path
    }
}

struct WorkerEventParser {
    private let decoder = JSONDecoder()

    func parse(_ line: String) throws -> WorkerEvent {
        let data = Data(line.utf8)
        return try decoder.decode(WorkerEvent.self, from: data)
    }
}
```

- [ ] **Step 3: Run event parser tests**

Run: `swift test --filter WorkerEventParserTests`

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/OtoChefApp/Services/WorkerEventParser.swift Tests/OtoChefAppTests/WorkerEventParserTests.swift
git commit -m "feat: parse worker progress events"
```

---

### Task 4: Python Worker Package And Models

**Files:**
- Create: `worker/pyproject.toml`
- Create: `worker/environment.yml`
- Create: `worker/otochef_worker/__init__.py`
- Create: `worker/otochef_worker/models.py`
- Create: `worker/otochef_worker/events.py`
- Create: `worker/tests/test_models.py`
- Create: `worker/tests/test_events.py`
- Create: `script/setup_conda_env.sh`

- [ ] **Step 1: Write model and event tests**

Create `worker/tests/test_models.py`:

```python
from pathlib import Path

from otochef_worker.models import Job, ASRSettings, TranslationSettings, ToolSettings, VideoSettings


def test_job_from_dict_accepts_swift_json_shape(tmp_path: Path) -> None:
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": "/tmp/audio.wav",
            "imagePath": "/tmp/image.png",
            "outputDirectory": str(tmp_path),
            "settings": {
                "asr": {
                    "backend": "fasterWhisper",
                    "model": "Systran/faster-whisper-large-v3",
                    "device": "auto",
                    "computeType": "auto",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 5,
                },
                "translation": {
                    "backend": "api",
                    "endpoint": "http://localhost:11434/v1",
                    "model": "qwen2.5:7b",
                    "prompt": "Translate",
                    "timeoutSeconds": 120,
                    "retryLimit": 2,
                },
                "tools": {"ffmpegPath": "/opt/homebrew/bin/ffmpeg"},
                "video": {"width": 1920, "height": 1080, "imageFit": "contain", "backgroundColor": "black"},
            },
        }
    )

    assert job.asr.model == "Systran/faster-whisper-large-v3"
    assert job.translation.backend == "api"
    assert job.output_directory == tmp_path
```

Create `worker/tests/test_events.py`:

```python
import json

from otochef_worker.events import event_json


def test_event_json_uses_worker_event_shape() -> None:
    line = event_json("stage_started", stage="asr", message="Transcribing audio")

    payload = json.loads(line)

    assert payload == {
        "type": "stage_started",
        "stage": "asr",
        "message": "Transcribing audio",
    }
```

- [ ] **Step 2: Add Python package config**

Create `worker/pyproject.toml`:

```toml
[project]
name = "otochef-worker"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
  "faster-whisper>=1.1.0",
  "requests>=2.32.0",
]

[project.optional-dependencies]
test = [
  "pytest>=8.0.0",
]

[tool.pytest.ini_options]
pythonpath = ["."]
testpaths = ["tests"]
```

Create `worker/environment.yml`:

```yaml
name: otochef
channels:
  - conda-forge
dependencies:
  - python=3.11
  - pip
  - ffmpeg
  - pip:
      - -e .[test]
```

- [ ] **Step 3: Implement worker models**

Create `worker/otochef_worker/__init__.py`:

```python
__all__ = ["__version__"]

__version__ = "0.1.0"
```

Create `worker/otochef_worker/models.py`:

```python
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ASRSettings:
    backend: str
    model: str
    device: str
    compute_type: str
    language: str
    vad_enabled: bool
    beam_size: int


@dataclass(frozen=True)
class TranslationSettings:
    backend: str
    endpoint: str
    model: str
    prompt: str
    timeout_seconds: int
    retry_limit: int


@dataclass(frozen=True)
class ToolSettings:
    ffmpeg_path: Path


@dataclass(frozen=True)
class VideoSettings:
    width: int
    height: int
    image_fit: str
    background_color: str


@dataclass(frozen=True)
class Job:
    job_id: str
    audio_path: Path
    image_path: Path
    output_directory: Path
    asr: ASRSettings
    translation: TranslationSettings
    tools: ToolSettings
    video: VideoSettings

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "Job":
        settings = payload["settings"]
        asr = settings["asr"]
        translation = settings["translation"]
        tools = settings["tools"]
        video = settings["video"]

        return cls(
            job_id=str(payload["id"]),
            audio_path=Path(payload["audioPath"]),
            image_path=Path(payload["imagePath"]),
            output_directory=Path(payload["outputDirectory"]),
            asr=ASRSettings(
                backend=asr["backend"],
                model=asr["model"],
                device=asr["device"],
                compute_type=asr["computeType"],
                language=asr["language"],
                vad_enabled=bool(asr["vadEnabled"]),
                beam_size=int(asr["beamSize"]),
            ),
            translation=TranslationSettings(
                backend=translation["backend"],
                endpoint=translation["endpoint"],
                model=translation["model"],
                prompt=translation["prompt"],
                timeout_seconds=int(translation["timeoutSeconds"]),
                retry_limit=int(translation["retryLimit"]),
            ),
            tools=ToolSettings(ffmpeg_path=Path(tools["ffmpegPath"])),
            video=VideoSettings(
                width=int(video["width"]),
                height=int(video["height"]),
                image_fit=video["imageFit"],
                background_color=video["backgroundColor"],
            ),
        )
```

- [ ] **Step 4: Implement event JSON helper**

Create `worker/otochef_worker/events.py`:

```python
from __future__ import annotations

import json
from typing import Any


def event_json(event_type: str, **fields: Any) -> str:
    payload = {"type": event_type}
    payload.update({key: value for key, value in fields.items() if value is not None})
    return json.dumps(payload, ensure_ascii=False)
```

- [ ] **Step 5: Add conda setup script**

Create `script/setup_conda_env.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONDA_EXE="${CONDA_EXE:-conda}"

cd "$ROOT_DIR/worker"
"$CONDA_EXE" env update -f environment.yml --prune
```

Run: `chmod +x script/setup_conda_env.sh`

- [ ] **Step 6: Run Python tests through current Python if available**

Run: `cd worker && python -m pytest tests/test_models.py tests/test_events.py -q`

Expected: tests pass when pytest is installed. If pytest is missing, run `./script/setup_conda_env.sh` first and then `cd worker && conda run -n otochef pytest tests/test_models.py tests/test_events.py -q`.

- [ ] **Step 7: Commit**

```bash
git add worker script/setup_conda_env.sh
git commit -m "feat: add Python worker package"
```

---

### Task 5: Python Subtitle Rendering

**Files:**
- Create: `worker/otochef_worker/subtitles.py`
- Create: `worker/tests/test_subtitles.py`

- [ ] **Step 1: Write subtitle tests**

Create `worker/tests/test_subtitles.py`:

```python
from otochef_worker.subtitles import SubtitleSegment, render_srt, render_ass


def test_render_srt_formats_times_and_text() -> None:
    segments = [SubtitleSegment(segment_id="s1", start=1.2, end=3.45, text="你好，世界")]

    srt = render_srt(segments)

    assert "1\n00:00:01,200 --> 00:00:03,450\n你好，世界\n" in srt


def test_render_ass_escapes_newlines() -> None:
    segments = [SubtitleSegment(segment_id="s1", start=0.0, end=2.0, text="第一行\n第二行")]

    ass = render_ass(segments, width=1920, height=1080)

    assert "PlayResX: 1920" in ass
    assert "Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,第一行\\N第二行" in ass
```

- [ ] **Step 2: Implement subtitle renderer**

Create `worker/otochef_worker/subtitles.py`:

```python
from __future__ import annotations

from dataclasses import dataclass
import textwrap


@dataclass(frozen=True)
class SubtitleSegment:
    segment_id: str
    start: float
    end: float
    text: str


def _srt_time(seconds: float) -> str:
    millis = round(seconds * 1000)
    hours, remainder = divmod(millis, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, ms = divmod(remainder, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02},{ms:03}"


def _ass_time(seconds: float) -> str:
    centis = round(seconds * 100)
    hours, remainder = divmod(centis, 360_000)
    minutes, remainder = divmod(remainder, 6_000)
    secs, cs = divmod(remainder, 100)
    return f"{hours}:{minutes:02}:{secs:02}.{cs:02}"


def _wrap_text(text: str, width: int = 24) -> str:
    lines: list[str] = []
    for raw_line in text.splitlines() or [text]:
        wrapped = textwrap.wrap(raw_line, width=width, break_long_words=False, replace_whitespace=False)
        lines.extend(wrapped or [raw_line])
    return "\n".join(lines)


def render_srt(segments: list[SubtitleSegment]) -> str:
    blocks: list[str] = []
    for index, segment in enumerate(segments, start=1):
        text = _wrap_text(segment.text)
        blocks.append(f"{index}\n{_srt_time(segment.start)} --> {_srt_time(segment.end)}\n{text}\n")
    return "\n".join(blocks)


def render_ass(segments: list[SubtitleSegment], width: int, height: int) -> str:
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Helvetica,54,&H00FFFFFF,&H00111111,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,80,80,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = [header]
    for segment in segments:
        text = _wrap_text(segment.text).replace("\n", r"\N")
        lines.append(f"Dialogue: 0,{_ass_time(segment.start)},{_ass_time(segment.end)},Default,,0,0,0,,{text}\n")
    return "".join(lines)
```

- [ ] **Step 3: Run subtitle tests**

Run: `cd worker && python -m pytest tests/test_subtitles.py -q`

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add worker/otochef_worker/subtitles.py worker/tests/test_subtitles.py
git commit -m "feat: render subtitle files"
```

---

### Task 6: Python Translation Providers

**Files:**
- Create: `worker/otochef_worker/translation.py`
- Create: `worker/tests/test_translation.py`

- [ ] **Step 1: Write translation batching tests**

Create `worker/tests/test_translation.py`:

```python
from otochef_worker.translation import TranscriptSegment, parse_translation_response, build_translation_payload


def test_build_translation_payload_preserves_segment_ids() -> None:
    segments = [
        TranscriptSegment(segment_id="s1", start=0.0, end=1.0, text="こんにちは"),
        TranscriptSegment(segment_id="s2", start=1.0, end=2.0, text="世界"),
    ]

    payload = build_translation_payload(segments)

    assert payload == [
        {"id": "s1", "text": "こんにちは"},
        {"id": "s2", "text": "世界"},
    ]


def test_parse_translation_response_reads_json_array() -> None:
    content = '[{"id":"s1","text":"你好"},{"id":"s2","text":"世界"}]'

    translations = parse_translation_response(content)

    assert translations == {"s1": "你好", "s2": "世界"}
```

- [ ] **Step 2: Implement translation helpers and client**

Create `worker/otochef_worker/translation.py`:

```python
from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Protocol

import requests

from .models import TranslationSettings


@dataclass(frozen=True)
class TranscriptSegment:
    segment_id: str
    start: float
    end: float
    text: str


class TranslationProvider(Protocol):
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        raise NotImplementedError


def build_translation_payload(segments: list[TranscriptSegment]) -> list[dict[str, str]]:
    return [{"id": segment.segment_id, "text": segment.text} for segment in segments]


def parse_translation_response(content: str) -> dict[str, str]:
    payload = json.loads(content)
    if not isinstance(payload, list):
        raise ValueError("Translation response must be a JSON array")
    result: dict[str, str] = {}
    for item in payload:
        result[str(item["id"])] = str(item["text"])
    return result


class OpenAICompatibleTranslationProvider:
    def __init__(self, settings: TranslationSettings, api_key: str | None = None):
        self.settings = settings
        self.api_key = api_key

    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        user_payload = json.dumps(build_translation_payload(segments), ensure_ascii=False)
        response = requests.post(
            f"{self.settings.endpoint.rstrip('/')}/chat/completions",
            headers=headers,
            timeout=self.settings.timeout_seconds,
            json={
                "model": self.settings.model,
                "messages": [
                    {"role": "system", "content": self.settings.prompt},
                    {"role": "user", "content": user_payload},
                ],
                "temperature": 0.2,
            },
        )
        response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
        return parse_translation_response(content)
```

- [ ] **Step 3: Run translation tests**

Run: `cd worker && python -m pytest tests/test_translation.py -q`

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add worker/otochef_worker/translation.py worker/tests/test_translation.py
git commit -m "feat: add translation provider contract"
```

---

### Task 7: Python ASR Provider

**Files:**
- Create: `worker/otochef_worker/asr.py`
- Modify: `worker/tests/test_translation.py`
- Create: `worker/tests/test_asr.py`

- [ ] **Step 1: Write ASR conversion test**

Create `worker/tests/test_asr.py`:

```python
from types import SimpleNamespace

from otochef_worker.asr import segments_from_faster_whisper


def test_segments_from_faster_whisper_assigns_stable_ids() -> None:
    raw_segments = [
        SimpleNamespace(start=0.0, end=1.25, text=" こんにちは "),
        SimpleNamespace(start=1.25, end=2.5, text="世界"),
    ]

    segments = segments_from_faster_whisper(raw_segments)

    assert [segment.segment_id for segment in segments] == ["seg-0001", "seg-0002"]
    assert segments[0].text == "こんにちは"
    assert segments[1].start == 1.25
```

- [ ] **Step 2: Implement ASR provider**

Create `worker/otochef_worker/asr.py`:

```python
from __future__ import annotations

from pathlib import Path
from typing import Iterable, Protocol, Any

from .models import ASRSettings
from .translation import TranscriptSegment


class ASRProvider(Protocol):
    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        raise NotImplementedError


def segments_from_faster_whisper(raw_segments: Iterable[Any]) -> list[TranscriptSegment]:
    segments: list[TranscriptSegment] = []
    for index, raw in enumerate(raw_segments, start=1):
        segments.append(
            TranscriptSegment(
                segment_id=f"seg-{index:04}",
                start=float(raw.start),
                end=float(raw.end),
                text=str(raw.text).strip(),
            )
        )
    return segments


class FasterWhisperASRProvider:
    def __init__(self, settings: ASRSettings):
        self.settings = settings

    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        from faster_whisper import WhisperModel

        device = "auto" if self.settings.device == "auto" else self.settings.device
        compute_type = "default" if self.settings.compute_type == "auto" else self.settings.compute_type
        model = WhisperModel(self.settings.model, device=device, compute_type=compute_type)
        raw_segments, _info = model.transcribe(
            str(audio_path),
            language=self.settings.language,
            beam_size=self.settings.beam_size,
            vad_filter=self.settings.vad_enabled,
        )
        return segments_from_faster_whisper(raw_segments)
```

- [ ] **Step 3: Run ASR test**

Run: `cd worker && python -m pytest tests/test_asr.py -q`

Expected: tests pass without loading a real faster-whisper model.

- [ ] **Step 4: Commit**

```bash
git add worker/otochef_worker/asr.py worker/tests/test_asr.py
git commit -m "feat: add faster-whisper ASR provider"
```

---

### Task 8: Python FFmpeg Command Builder

**Files:**
- Create: `worker/otochef_worker/ffmpeg.py`
- Create: `worker/tests/test_ffmpeg.py`

- [ ] **Step 1: Write FFmpeg command test**

Create `worker/tests/test_ffmpeg.py`:

```python
from pathlib import Path

from otochef_worker.ffmpeg import build_ffmpeg_command
from otochef_worker.models import VideoSettings


def test_build_ffmpeg_command_contains_static_image_audio_and_ass() -> None:
    command = build_ffmpeg_command(
        ffmpeg_path=Path("/usr/local/bin/ffmpeg"),
        image_path=Path("/tmp/image.png"),
        audio_path=Path("/tmp/audio.wav"),
        ass_path=Path("/tmp/subtitles.zh.ass"),
        output_path=Path("/tmp/output.mp4"),
        video=VideoSettings(width=1920, height=1080, image_fit="contain", background_color="black"),
    )

    command_text = " ".join(command)

    assert command[:3] == ["/usr/local/bin/ffmpeg", "-y", "-loop"]
    assert "scale=w=1920:h=1080:force_original_aspect_ratio=decrease" in command_text
    assert "subtitles=/tmp/subtitles.zh.ass" in command_text
    assert command[-1] == "/tmp/output.mp4"
```

- [ ] **Step 2: Implement FFmpeg command builder**

Create `worker/otochef_worker/ffmpeg.py`:

```python
from __future__ import annotations

from pathlib import Path
import subprocess

from .models import VideoSettings


def build_ffmpeg_command(
    ffmpeg_path: Path,
    image_path: Path,
    audio_path: Path,
    ass_path: Path,
    output_path: Path,
    video: VideoSettings,
) -> list[str]:
    if video.image_fit == "contain":
        scale = (
            f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=decrease,"
            f"pad={video.width}:{video.height}:(ow-iw)/2:(oh-ih)/2:color={video.background_color}"
        )
    else:
        scale = (
            f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=increase,"
            f"crop={video.width}:{video.height}"
        )

    video_filter = f"{scale},subtitles={ass_path}"
    return [
        str(ffmpeg_path),
        "-y",
        "-loop",
        "1",
        "-i",
        str(image_path),
        "-i",
        str(audio_path),
        "-vf",
        video_filter,
        "-c:v",
        "libx264",
        "-tune",
        "stillimage",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-pix_fmt",
        "yuv420p",
        "-shortest",
        str(output_path),
    ]


def run_ffmpeg(command: list[str]) -> None:
    subprocess.run(command, check=True, text=True, capture_output=True)
```

- [ ] **Step 3: Run FFmpeg tests**

Run: `cd worker && python -m pytest tests/test_ffmpeg.py -q`

Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add worker/otochef_worker/ffmpeg.py worker/tests/test_ffmpeg.py
git commit -m "feat: build FFmpeg render command"
```

---

### Task 9: Python Pipeline And CLI

**Files:**
- Create: `worker/otochef_worker/pipeline.py`
- Create: `worker/otochef_worker/__main__.py`
- Create: `worker/tests/test_pipeline.py`

- [ ] **Step 1: Write pipeline test with fake providers**

Create `worker/tests/test_pipeline.py`:

```python
import json
from pathlib import Path

from otochef_worker.models import Job
from otochef_worker.pipeline import run_pipeline
from otochef_worker.translation import TranscriptSegment


class FakeASR:
    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        return [TranscriptSegment(segment_id="seg-0001", start=0.0, end=1.0, text="こんにちは")]


class FakeTranslator:
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        return {"seg-0001": "你好"}


def test_run_pipeline_writes_transcript_translation_and_subtitles(tmp_path: Path) -> None:
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": str(tmp_path / "audio.wav"),
            "imagePath": str(tmp_path / "image.png"),
            "outputDirectory": str(tmp_path),
            "settings": {
                "asr": {
                    "backend": "fasterWhisper",
                    "model": "Systran/faster-whisper-large-v3",
                    "device": "auto",
                    "computeType": "auto",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 5,
                },
                "translation": {
                    "backend": "api",
                    "endpoint": "http://localhost:11434/v1",
                    "model": "qwen2.5:7b",
                    "prompt": "Translate",
                    "timeoutSeconds": 120,
                    "retryLimit": 2,
                },
                "tools": {"ffmpegPath": "/opt/homebrew/bin/ffmpeg"},
                "video": {"width": 1920, "height": 1080, "imageFit": "contain", "backgroundColor": "black"},
            },
        }
    )

    artifacts = run_pipeline(job, asr=FakeASR(), translator=FakeTranslator(), run_video=False)

    assert artifacts.transcript_path.exists()
    assert artifacts.translation_path.exists()
    assert artifacts.srt_path.exists()
    assert artifacts.ass_path.exists()
    assert json.loads(artifacts.translation_path.read_text())["segments"][0]["text"] == "你好"
```

- [ ] **Step 2: Implement pipeline**

Create `worker/otochef_worker/pipeline.py`:

```python
from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
from typing import Protocol

from .asr import ASRProvider, FasterWhisperASRProvider
from .ffmpeg import build_ffmpeg_command, run_ffmpeg
from .models import Job
from .subtitles import SubtitleSegment, render_ass, render_srt
from .translation import OpenAICompatibleTranslationProvider, TranslationProvider


@dataclass(frozen=True)
class PipelineArtifacts:
    transcript_path: Path
    translation_path: Path
    srt_path: Path
    ass_path: Path
    output_video_path: Path


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def run_pipeline(
    job: Job,
    asr: ASRProvider | None = None,
    translator: TranslationProvider | None = None,
    run_video: bool = True,
) -> PipelineArtifacts:
    job.output_directory.mkdir(parents=True, exist_ok=True)
    asr_provider = asr or FasterWhisperASRProvider(job.asr)
    translation_provider = translator or OpenAICompatibleTranslationProvider(
        job.translation,
        api_key=os.environ.get("OTOCHEF_TRANSLATION_API_KEY"),
    )

    transcript_segments = asr_provider.transcribe(job.audio_path)
    transcript_path = job.output_directory / "transcript.ja.json"
    _write_json(
        transcript_path,
        {
            "segments": [
                {
                    "id": segment.segment_id,
                    "start": segment.start,
                    "end": segment.end,
                    "text": segment.text,
                }
                for segment in transcript_segments
            ]
        },
    )

    translated_text = translation_provider.translate(transcript_segments)
    subtitle_segments = [
        SubtitleSegment(
            segment_id=segment.segment_id,
            start=segment.start,
            end=segment.end,
            text=translated_text[segment.segment_id],
        )
        for segment in transcript_segments
    ]
    translation_path = job.output_directory / "translation.zh.json"
    _write_json(
        translation_path,
        {
            "segments": [
                {
                    "id": segment.segment_id,
                    "start": segment.start,
                    "end": segment.end,
                    "text": segment.text,
                }
                for segment in subtitle_segments
            ]
        },
    )

    srt_path = job.output_directory / "subtitles.zh.srt"
    ass_path = job.output_directory / "subtitles.zh.ass"
    srt_path.write_text(render_srt(subtitle_segments), encoding="utf-8")
    ass_path.write_text(render_ass(subtitle_segments, width=job.video.width, height=job.video.height), encoding="utf-8")

    output_video_path = job.output_directory / "output.mp4"
    if run_video:
        command = build_ffmpeg_command(
            ffmpeg_path=job.tools.ffmpeg_path,
            image_path=job.image_path,
            audio_path=job.audio_path,
            ass_path=ass_path,
            output_path=output_video_path,
            video=job.video,
        )
        run_ffmpeg(command)

    return PipelineArtifacts(
        transcript_path=transcript_path,
        translation_path=translation_path,
        srt_path=srt_path,
        ass_path=ass_path,
        output_video_path=output_video_path,
    )
```

- [ ] **Step 3: Implement CLI entrypoint**

Create `worker/otochef_worker/__main__.py`:

```python
from __future__ import annotations

import argparse
import json
import sys

from .events import event_json
from .models import Job
from .pipeline import run_pipeline


def main() -> int:
    parser = argparse.ArgumentParser(prog="otochef-worker")
    parser.add_argument("--job", required=True, help="Path to job.json")
    args = parser.parse_args()

    try:
        print(event_json("job_started", message="Job started"), flush=True)
        with open(args.job, "r", encoding="utf-8") as handle:
            job = Job.from_dict(json.load(handle))
        print(event_json("stage_started", stage="pipeline", message="Processing media"), flush=True)
        artifacts = run_pipeline(job)
        print(event_json("artifact_created", stage="video", path=str(artifacts.output_video_path)), flush=True)
        print(event_json("job_finished", message="Job finished"), flush=True)
        return 0
    except Exception as error:
        print(event_json("stage_failed", stage="pipeline", message=str(error)), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run pipeline tests**

Run: `cd worker && python -m pytest tests/test_pipeline.py -q`

Expected: tests pass without invoking FFmpeg.

- [ ] **Step 5: Commit**

```bash
git add worker/otochef_worker/pipeline.py worker/otochef_worker/__main__.py worker/tests/test_pipeline.py
git commit -m "feat: orchestrate worker pipeline"
```

---

### Task 10: Swift Worker Client And Job Store

**Files:**
- Create: `Sources/OtoChefApp/Services/JobFileWriter.swift`
- Create: `Sources/OtoChefApp/Services/APIKeyStore.swift`
- Create: `Sources/OtoChefApp/Services/PythonWorkerClient.swift`
- Create: `Sources/OtoChefApp/Stores/JobStore.swift`
- Modify: `Sources/OtoChefApp/Models/JobModels.swift`
- Create: `Tests/OtoChefAppTests/APIKeyStoreTests.swift`

- [ ] **Step 1: Add worker launch request and artifact types**

Append to `Sources/OtoChefApp/Models/JobModels.swift`:

```swift
struct JobArtifacts: Equatable {
    var workingDirectory: URL
    var jobFile: URL
}

struct WorkerLaunchRequest: Equatable {
    var condaPath: String
    var environmentName: String
    var workerDirectory: URL
    var jobFile: URL
    var environment: [String: String]
}
```

- [ ] **Step 2: Implement job file writer**

Create `Sources/OtoChefApp/Services/JobFileWriter.swift`:

```swift
import Foundation

struct JobFileWriter {
    private let encoder: JSONEncoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
    }

    func write(_ job: OtoChefJob) throws -> JobArtifacts {
        let safeID = job.id.uuidString.lowercased()
        let workingDirectory = URL(fileURLWithPath: job.outputDirectory)
            .appendingPathComponent("otochef-\(safeID)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let jobFile = workingDirectory.appendingPathComponent("job.json")
        var jobForWorker = job
        jobForWorker.outputDirectory = workingDirectory.path
        let data = try encoder.encode(jobForWorker)
        try data.write(to: jobFile, options: [.atomic])

        return JobArtifacts(workingDirectory: workingDirectory, jobFile: jobFile)
    }
}
```

- [ ] **Step 3: Write API key store test**

Create `Tests/OtoChefAppTests/APIKeyStoreTests.swift`:

```swift
import XCTest
@testable import OtoChefApp

final class APIKeyStoreTests: XCTestCase {
    func testMemoryAPIKeyStoreSavesAndLoadsTranslationKey() throws {
        let store = MemoryAPIKeyStore()

        try store.saveTranslationAPIKey("test-key")

        XCTAssertEqual(try store.loadTranslationAPIKey(), "test-key")
    }
}
```

- [ ] **Step 4: Implement API key store**

Create `Sources/OtoChefApp/Services/APIKeyStore.swift`:

```swift
import Foundation
import Security

protocol APIKeyStore {
    func saveTranslationAPIKey(_ key: String) throws
    func loadTranslationAPIKey() throws -> String?
}

final class MemoryAPIKeyStore: APIKeyStore {
    private var key: String?

    func saveTranslationAPIKey(_ key: String) throws {
        self.key = key
    }

    func loadTranslationAPIKey() throws -> String? {
        key
    }
}

final class KeychainAPIKeyStore: APIKeyStore {
    private let service = "OtoChef"
    private let account = "translation-api-key"

    func saveTranslationAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func loadTranslationAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        guard let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 5: Implement Python worker client**

Create `Sources/OtoChefApp/Services/PythonWorkerClient.swift`:

```swift
import Foundation

final class PythonWorkerClient {
    private let parser = WorkerEventParser()
    private var runningProcess: Process?

    func run(_ request: WorkerLaunchRequest, onEvent: @escaping (WorkerEvent) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: request.condaPath)
        process.arguments = [
            "run",
            "-n",
            request.environmentName,
            "python",
            "-m",
            "otochef_worker",
            "--job",
            request.jobFile.path
        ]
        process.currentDirectoryURL = request.workerDirectory
        var environment = ProcessInfo.processInfo.environment
        request.environment.forEach { key, value in
            environment[key] = value
        }
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [parser] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for line in text.split(separator: "\n") {
                if let event = try? parser.parse(String(line)) {
                    onEvent(event)
                }
            }
        }

        try process.run()
        runningProcess = process
    }
}
```

- [ ] **Step 6: Implement observable job store**

Create `Sources/OtoChefApp/Stores/JobStore.swift`:

```swift
import Foundation
import Observation

@Observable
final class JobStore {
    var draft = JobDraft(audioURL: nil, imageURL: nil, outputDirectory: nil, settings: .defaults)
    var validationErrors: [JobValidationError] = []
    var events: [WorkerEvent] = []
    var isRunning = false

    private let validator = JobValidator()
    private let writer = JobFileWriter()
    private let worker = PythonWorkerClient()
    private let apiKeyStore: any APIKeyStore

    init(apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()) {
        self.apiKeyStore = apiKeyStore
    }

    func validate() {
        validationErrors = validator.validate(draft)
    }

    func canStart() -> Bool {
        validator.validate(draft).isEmpty && !isRunning
    }

    func append(event: WorkerEvent) {
        events.append(event)
        if event.type == .jobFinished || event.type == .stageFailed {
            isRunning = false
        }
    }

    func startProcessing() {
        validate()
        guard validationErrors.isEmpty else {
            return
        }

        do {
            let job = try validator.makeJob(from: draft)
            let artifacts = try writer.write(job)
            let apiKey = try apiKeyStore.loadTranslationAPIKey()
            let workerDirectory = projectRoot()
                .appendingPathComponent("worker", isDirectory: true)
            let request = WorkerLaunchRequest(
                condaPath: draft.settings.conda.executablePath,
                environmentName: draft.settings.conda.environmentName,
                workerDirectory: workerDirectory,
                jobFile: artifacts.jobFile,
                environment: apiKey.map { ["OTOCHEF_TRANSLATION_API_KEY": $0] } ?? [:]
            )
            isRunning = true
            events.removeAll()
            try worker.run(request) { [weak self] event in
                DispatchQueue.main.async {
                    self?.append(event: event)
                }
            }
        } catch {
            isRunning = false
            events.append(
                WorkerEvent(
                    type: .stageFailed,
                    stage: "swift",
                    message: error.localizedDescription,
                    progress: nil,
                    path: nil
                )
            )
        }
    }

    private func projectRoot() -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            return bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
```

- [ ] **Step 7: Run Swift tests**

Run: `swift test`

Expected: all Swift tests pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/OtoChefApp/Services/JobFileWriter.swift Sources/OtoChefApp/Services/APIKeyStore.swift Sources/OtoChefApp/Services/PythonWorkerClient.swift Sources/OtoChefApp/Stores/JobStore.swift Sources/OtoChefApp/Models/JobModels.swift Tests/OtoChefAppTests/APIKeyStoreTests.swift
git commit -m "feat: connect Swift to Python worker"
```

---

### Task 11: SwiftUI Main Views

**Files:**
- Modify: `Sources/OtoChefApp/Views/ContentView.swift`
- Create: `Sources/OtoChefApp/Views/NewJobView.swift`
- Create: `Sources/OtoChefApp/Views/SettingsView.swift`
- Create: `Sources/OtoChefApp/Views/DiagnosticsView.swift`

- [ ] **Step 1: Replace `ContentView` with split navigation**

Update `Sources/OtoChefApp/Views/ContentView.swift`:

```swift
import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case newJob = "新任务"
    case recentJobs = "最近任务"
    case settings = "设置"
    case diagnostics = "诊断"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .newJob:
            return "plus.circle"
        case .recentJobs:
            return "clock"
        case .settings:
            return "gearshape"
        case .diagnostics:
            return "stethoscope"
        }
    }
}

struct ContentView: View {
    @State private var store = JobStore()
    @SceneStorage("selectedSection") private var selectedSectionRawValue = AppSection.newJob.rawValue

    private var selection: Binding<AppSection> {
        Binding {
            AppSection(rawValue: selectedSectionRawValue) ?? .newJob
        } set: { newValue in
            selectedSectionRawValue = newValue.rawValue
        }
    }

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
        } detail: {
            switch selection.wrappedValue {
            case .newJob:
                NewJobView(store: store)
            case .recentJobs:
                ContentUnavailableView("暂无最近任务", systemImage: "clock")
            case .settings:
                SettingsView(settings: $store.draft.settings)
            case .diagnostics:
                DiagnosticsView(store: store)
            }
        }
    }
}
```

- [ ] **Step 2: Add new job view**

Create `Sources/OtoChefApp/Views/NewJobView.swift`:

```swift
import SwiftUI

struct NewJobView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新任务")
                .font(.title)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                fileButton("选择音频", systemImage: "waveform", value: store.draft.audioURL?.lastPathComponent) {
                    chooseFile(allowedTypes: ["wav", "mp3", "m4a", "flac"]) { store.draft.audioURL = $0 }
                }
                fileButton("选择图片", systemImage: "photo", value: store.draft.imageURL?.lastPathComponent) {
                    chooseFile(allowedTypes: ["png", "jpg", "jpeg", "webp"]) { store.draft.imageURL = $0 }
                }
            }

            fileButton("选择输出文件夹", systemImage: "folder", value: store.draft.outputDirectory?.path) {
                chooseDirectory { store.draft.outputDirectory = $0 }
            }

            if !store.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.validationErrors) { error in
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            List(store.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message ?? event.type.rawValue)
                    if let path = event.path {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                store.startProcessing()
            } label: {
                Label("开始处理", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canStart())
        }
        .padding(24)
        .onChange(of: store.draft) {
            store.validate()
        }
    }

    private func fileButton(_ title: String, systemImage: String, value: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(value ?? "未选择")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
    }

    private func chooseFile(allowedTypes: [String], assign: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedFileTypes = allowedTypes
        if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }

    private func chooseDirectory(assign: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            assign(url)
        }
    }
}
```

- [ ] **Step 3: Add settings view**

Create `Sources/OtoChefApp/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @State private var apiKey = ""
    @State private var keychainMessage: String?
    private let apiKeyStore: any APIKeyStore = KeychainAPIKeyStore()

    var body: some View {
        Form {
            Section("语音识别") {
                TextField("模型路径或 ID", text: $settings.asr.model)
                Text("推荐：Systran/faster-whisper-large-v3")
                    .foregroundStyle(.secondary)
                Text("下载：https://huggingface.co/Systran/faster-whisper-large-v3")
                    .foregroundStyle(.secondary)
                TextField("设备", text: $settings.asr.device)
                TextField("计算类型", text: $settings.asr.computeType)
                Toggle("启用 VAD", isOn: $settings.asr.vadEnabled)
                Stepper("Beam Size: \(settings.asr.beamSize)", value: $settings.asr.beamSize, in: 1...10)
            }

            Section("翻译") {
                Picker("后端", selection: $settings.translation.backend) {
                    Text("本地").tag(TranslationBackend.local)
                    Text("API").tag(TranslationBackend.api)
                }
                TextField("Endpoint", text: $settings.translation.endpoint)
                TextField("模型", text: $settings.translation.model)
                SecureField("API Key", text: $apiKey)
                Button {
                    do {
                        try apiKeyStore.saveTranslationAPIKey(apiKey)
                        keychainMessage = "API Key 已保存到 Keychain"
                    } catch {
                        keychainMessage = "API Key 保存失败：\(error.localizedDescription)"
                    }
                } label: {
                    Label("保存 API Key", systemImage: "key")
                }
                if let keychainMessage {
                    Text(keychainMessage)
                        .foregroundStyle(.secondary)
                }
                TextEditor(text: $settings.translation.prompt)
                    .frame(minHeight: 80)
            }

            Section("工具") {
                TextField("Conda", text: $settings.conda.executablePath)
                TextField("Conda 环境", text: $settings.conda.environmentName)
                TextField("FFmpeg", text: $settings.tools.ffmpegPath)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}
```

- [ ] **Step 4: Add diagnostics view**

Create `Sources/OtoChefApp/Views/DiagnosticsView.swift`:

```swift
import SwiftUI

struct DiagnosticsView: View {
    @Bindable var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("诊断")
                .font(.title)
                .fontWeight(.semibold)

            Button {
                store.validate()
            } label: {
                Label("运行预检", systemImage: "checkmark.seal")
            }
            .buttonStyle(.borderedProminent)

            if store.validationErrors.isEmpty {
                Label("当前配置通过基础预检", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                ForEach(store.validationErrors) { error in
                    Label(error.message, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                }
            }
            Spacer()
        }
        .padding(24)
    }
}
```

- [ ] **Step 5: Build Swift app**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/OtoChefApp/Views
git commit -m "feat: build OtoChef macOS UI"
```

---

### Task 12: Build And Run Scripts

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [ ] **Step 1: Add SwiftPM GUI run script**

Create `script/build_and_run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="OtoChef"
BUNDLE_ID="com.otochef.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
```

Run: `chmod +x script/build_and_run.sh`

- [ ] **Step 2: Add Codex Run action**

Create `.codex/environments/environment.toml`:

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "OtoChef"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 3: Verify build script**

Run: `./script/build_and_run.sh --verify`

Expected: Swift package builds, `dist/OtoChef.app` is created, and `pgrep -x OtoChef` succeeds.

- [ ] **Step 4: Commit**

```bash
git add script/build_and_run.sh .codex/environments/environment.toml
git commit -m "chore: add macOS run script"
```

---

### Task 13: End-To-End Verification Pass

**Files:**
- Modify only files required by failures from this task.

- [ ] **Step 1: Run Swift tests**

Run: `swift test`

Expected: all Swift tests pass.

- [ ] **Step 2: Run Python tests**

Run: `cd worker && python -m pytest -q`

Expected: all Python tests pass when pytest is installed. If pytest is missing, run `./script/setup_conda_env.sh`, then `cd worker && conda run -n otochef pytest -q`.

- [ ] **Step 3: Build app**

Run: `swift build`

Expected: build succeeds.

- [ ] **Step 4: Run app verification**

Run: `./script/build_and_run.sh --verify`

Expected: `dist/OtoChef.app` launches and `pgrep -x OtoChef` succeeds.

- [ ] **Step 5: Commit verification fixes**

If Step 1 through Step 4 required code fixes, commit them:

```bash
git add Package.swift Sources Tests worker script .codex
git commit -m "fix: complete OtoChef MVP verification"
```

If no files changed, record the verification commands and results in the final implementation summary.

---

## Spec Coverage Checklist

- Native macOS UI: Tasks 1, 10, 11, 12.
- Conda Python worker: Tasks 4, 9.
- Faster-whisper ASR with `Systran/faster-whisper-large-v3` default: Tasks 1, 4, 7, 11.
- Local/API translation shape: Tasks 1, 6, 11.
- SRT and ASS subtitle output: Tasks 5, 9.
- FFmpeg still-image MP4 output: Tasks 8, 9.
- JSON job and JSONL events: Tasks 3, 9, 10.
- Keychain API key storage: Tasks 10, 11.
- Preflight and validation: Tasks 2, 11.
- Testing strategy: Tasks 1 through 9 and 13.
