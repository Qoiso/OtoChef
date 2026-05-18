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
    assert job.output_directory == tmp_path


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
