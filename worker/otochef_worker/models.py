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
    cpu_threads: int


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
                cpu_threads=int(asr.get("cpuThreads", 8)),
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
