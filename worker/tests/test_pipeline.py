import json
from pathlib import Path
import re

import pytest

from otochef_worker.models import Job
from otochef_worker.pipeline import _read_transcript_segments, run_pipeline
from otochef_worker.translation import TranscriptSegment


class FakeASR:
    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        return [TranscriptSegment(segment_id="seg-0001", start=0.0, end=1.0, text="こんにちは")]


class FakeTranslator:
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        return {"seg-0001": "你好"}


class MissingSegmentTranslator:
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        return {}


class ExplodingTranslator:
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        raise AssertionError("translation should be skipped")


def test_read_transcript_segments_removes_whisperkit_control_tokens(tmp_path: Path) -> None:
    transcript_path = tmp_path / "transcript.ja.json"
    transcript_path.write_text(
        json.dumps(
            {
                "segments": [
                    {
                        "id": "seg-0001",
                        "start": 0.0,
                        "end": 1.0,
                        "text": "<|startoftranscript|><|ja|><|transcribe|><|0.00|>こんにちは<|1.00|><|endoftext|>",
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    segments = _read_transcript_segments(transcript_path)

    assert segments == [TranscriptSegment(segment_id="seg-0001", start=0.0, end=1.0, text="こんにちは")]


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
    assert artifacts.output_video_path is None
    assert json.loads(artifacts.translation_path.read_text())["segments"][0]["text"] == "你好"


def test_run_pipeline_writes_only_japanese_subtitles_without_translation(tmp_path: Path) -> None:
    internal_dir = tmp_path / ".otochef" / "example"
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": str(tmp_path / "audio.wav"),
            "imagePath": "",
            "outputDirectory": str(tmp_path),
            "workingDirectory": str(internal_dir),
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
                "video": {
                    "width": 1920,
                    "height": 1080,
                    "imageFit": "contain",
                    "backgroundColor": "black",
                    "outputFiles": ["japaneseSubtitles"],
                },
            },
        }
    )

    artifacts = run_pipeline(job, asr=FakeASR(), translator=ExplodingTranslator(), run_video=False)

    assert artifacts.translation_path is None
    assert (tmp_path / "subtitles.ja.srt").exists()
    assert (tmp_path / "subtitles.ja.ass").exists()
    assert not (tmp_path / "subtitles.zh.srt").exists()
    assert not (tmp_path / "transcript.ja.json").exists()
    assert (internal_dir / "transcript.ja.json").exists()


def test_run_pipeline_reports_missing_translation_ids_before_subtitle_generation(tmp_path: Path) -> None:
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

    with pytest.raises(ValueError, match="missing translations.*seg-0001"):
        run_pipeline(job, asr=FakeASR(), translator=MissingSegmentTranslator(), run_video=False)


def test_run_pipeline_external_subtitles_skips_video_even_when_run_video_is_true(tmp_path: Path) -> None:
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
                "tools": {"ffmpegPath": "/definitely/not/ffmpeg"},
                "video": {
                    "width": 1920,
                    "height": 1080,
                    "imageFit": "contain",
                    "backgroundColor": "black",
                    "subtitleOutputMode": "external",
                },
            },
        }
    )

    artifacts = run_pipeline(job, asr=FakeASR(), translator=FakeTranslator(), run_video=True)

    assert artifacts.output_video_path is None
    assert not (tmp_path / "output.mp4").exists()
    assert not (tmp_path / "output.mkv").exists()


def test_run_pipeline_hard_subtitles_fail_when_ffmpeg_cannot_burn_ass(tmp_path: Path, monkeypatch) -> None:
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
                "video": {
                    "width": 1920,
                    "height": 1080,
                    "imageFit": "contain",
                    "backgroundColor": "black",
                    "subtitleOutputMode": "mp4HardSubtitles",
                },
            },
        }
    )
    monkeypatch.setattr("otochef_worker.pipeline.ffmpeg_supports_filter", lambda *_args: False)

    with pytest.raises(RuntimeError, match="无法生成 MP4 硬字幕"):
        run_pipeline(job, asr=FakeASR(), translator=FakeTranslator(), run_video=True)


def test_run_pipeline_uses_existing_transcript_and_skips_asr(tmp_path: Path) -> None:
    transcript_path = tmp_path / "transcript.ja.json"
    transcript_path.write_text(
        json.dumps(
            {
                "segments": [
                    {
                        "id": "seg-0001",
                        "start": 0.0,
                        "end": 1.0,
                        "text": "こんにちは",
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": str(tmp_path / "audio.wav"),
            "imagePath": str(tmp_path / "image.png"),
            "outputDirectory": str(tmp_path),
            "settings": {
                "asr": {
                    "backend": "whisperKit",
                    "model": "large-v3-v20240930_626MB",
                    "modelFolder": "Models/whisperkit",
                    "device": "coreML",
                    "computeType": "all",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
                    "cpuThreads": 8,
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

    class ExplodingASR:
        def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
            raise AssertionError("ASR should be skipped when transcript.ja.json already exists")

    artifacts = run_pipeline(job, asr=ExplodingASR(), translator=FakeTranslator(), run_video=False)

    assert artifacts.transcript_path == transcript_path
    assert json.loads(artifacts.translation_path.read_text())["segments"][0]["text"] == "你好"


def test_run_pipeline_requires_native_whisperkit_transcript_when_asr_provider_is_not_injected(tmp_path: Path) -> None:
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

    with pytest.raises(RuntimeError, match="WhisperKit transcript.ja.json is missing"):
        run_pipeline(job, translator=FakeTranslator(), run_video=False)


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

    stage_events = [
        (event_type, fields.get("stage"))
        for event_type, fields in events
        if not (event_type == "progress" and fields.get("stage") == "translation")
    ]
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


def test_run_pipeline_emits_translation_duration_event(tmp_path: Path) -> None:
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

    run_pipeline(
        job,
        asr=FakeASR(),
        translator=FakeTranslator(),
        run_video=False,
        emit=lambda event_type, **fields: events.append((event_type, fields)),
    )

    duration_messages = [
        fields["message"]
        for event_type, fields in events
        if event_type == "progress" and fields.get("stage") == "translation"
    ]
    assert any(re.search(r"翻译请求完成，用时 \d+\.\d+ 秒", message) for message in duration_messages)
