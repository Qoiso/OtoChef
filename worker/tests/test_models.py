from pathlib import Path

from otochef_worker.models import Job


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

    assert job.asr.model == "Systran/faster-whisper-large-v3"
    assert job.asr.cpu_threads == 8
    assert job.translation.backend == "api"
    assert job.translation.selected_provider == "openAICompatible"
    assert job.translation.active_configuration.base_url == "http://localhost:11434/v1"
    assert job.translation.active_configuration.model == "qwen2.5:7b"
    assert job.output_directory == tmp_path
    assert job.working_directory == tmp_path
    assert job.video.subtitle_output_mode == "external"
    assert job.video.output_files == ("chineseSubtitles",)


def test_job_from_dict_parses_selected_translation_provider(tmp_path: Path) -> None:
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": "/tmp/audio.wav",
            "imagePath": "/tmp/image.png",
            "outputDirectory": str(tmp_path),
            "settings": {
                "asr": {
                    "backend": "whisperKit",
                    "model": "large-v3-v20240930_626MB",
                    "device": "coreML",
                    "computeType": "all",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
                    "cpuThreads": 8,
                },
                "translation": {
                    "backend": "api",
                    "selectedProvider": "claude",
                    "providerConfigurations": [
                        {
                            "provider": "claude",
                            "baseURL": "https://api.anthropic.com",
                            "model": "claude-sonnet-4-5-20250929",
                        },
                        {"provider": "openAI", "baseURL": "https://api.openai.com/v1", "model": "gpt-5"},
                    ],
                    "prompt": "Translate",
                    "timeoutSeconds": 120,
                    "retryLimit": 2,
                },
                "tools": {"ffmpegPath": "/opt/homebrew/bin/ffmpeg"},
                "video": {"width": 1920, "height": 1080, "imageFit": "contain", "backgroundColor": "black"},
            },
        }
    )

    assert job.translation.selected_provider == "claude"
    assert job.translation.active_configuration.base_url == "https://api.anthropic.com"
    assert job.translation.active_configuration.model == "claude-sonnet-4-5-20250929"


def test_job_from_dict_defaults_cpu_threads_for_older_jobs(tmp_path: Path) -> None:
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
                    "device": "cpu",
                    "computeType": "int8",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
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

    assert job.asr.cpu_threads == 8


def test_job_from_dict_accepts_subtitle_output_mode(tmp_path: Path) -> None:
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
                    "device": "cpu",
                    "computeType": "int8",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
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
                    "subtitleOutputMode": "mkvSoftAss",
                },
            },
        }
    )

    assert job.video.subtitle_output_mode == "mkvSoftAss"
    assert job.video.output_files == ("video", "chineseSubtitles")


def test_job_from_dict_accepts_output_files_and_working_directory(tmp_path: Path) -> None:
    working_directory = tmp_path / ".otochef" / "example"
    job = Job.from_dict(
        {
            "id": "example",
            "audioPath": "/tmp/audio.wav",
            "imagePath": "",
            "outputDirectory": str(tmp_path),
            "workingDirectory": str(working_directory),
            "settings": {
                "asr": {
                    "backend": "fasterWhisper",
                    "model": "Systran/faster-whisper-large-v3",
                    "device": "cpu",
                    "computeType": "int8",
                    "language": "ja",
                    "vadEnabled": True,
                    "beamSize": 1,
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
                    "outputFiles": ["bilingualSubtitles", "japaneseSubtitles"],
                },
            },
        }
    )

    assert job.working_directory == working_directory
    assert job.video.output_files == ("japaneseSubtitles", "bilingualSubtitles")


def test_job_from_dict_accepts_localized_video_input(tmp_path: Path) -> None:
    job = Job.from_dict(
        {
            "id": "example",
            "inputKind": "video",
            "audioPath": str(tmp_path / ".otochef" / "example" / "source-audio.wav"),
            "videoPath": str(tmp_path / "source.mp4"),
            "imagePath": "",
            "outputDirectory": str(tmp_path),
            "workingDirectory": str(tmp_path / ".otochef" / "example"),
            "settings": {
                "asr": {
                    "backend": "whisperKit",
                    "model": "large-v3-v20240930_626MB",
                    "device": "coreML",
                    "computeType": "all",
                    "language": "",
                    "vadEnabled": True,
                    "beamSize": 1,
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
                    "outputFiles": ["video", "chineseSubtitles"],
                },
            },
        }
    )

    assert job.input_kind == "video"
    assert job.source_video_path == tmp_path / "source.mp4"
    assert job.audio_path.name == "source-audio.wav"
