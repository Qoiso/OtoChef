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


def test_run_pipeline_emits_stage_events(tmp_path: Path) -> None:
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
    events: list[tuple[str, dict]] = []

    artifacts = run_pipeline(
        job,
        asr=FakeASR(),
        translator=FakeTranslator(),
        run_video=False,
        emit=lambda event_type, **fields: events.append((event_type, fields)),
    )

    stage_events = [(event_type, fields.get("stage")) for event_type, fields in events]
    assert stage_events == [
        ("stage_started", "asr"),
        ("artifact_created", "asr"),
        ("stage_started", "translation"),
        ("artifact_created", "translation"),
        ("stage_started", "subtitle"),
        ("artifact_created", "subtitle"),
        ("artifact_created", "subtitle"),
    ]
    assert events[1][1]["path"] == str(artifacts.transcript_path)
