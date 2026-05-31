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
    model_folder: str = "Models/whisperkit"


@dataclass(frozen=True)
class TranslationProviderConfiguration:
    provider: str
    base_url: str
    model: str


@dataclass(frozen=True)
class TranslationSettings:
    backend: str
    selected_provider: str
    provider_configurations: tuple[TranslationProviderConfiguration, ...]
    prompt: str
    timeout_seconds: int
    retry_limit: int

    @property
    def active_configuration(self) -> TranslationProviderConfiguration:
        for configuration in self.provider_configurations:
            if configuration.provider == self.selected_provider:
                return configuration
        raise ValueError(f"Missing configuration for translation provider: {self.selected_provider}")


@dataclass(frozen=True)
class ToolSettings:
    ffmpeg_path: Path


@dataclass(frozen=True)
class VideoSettings:
    width: int
    height: int
    image_fit: str
    background_color: str
    subtitle_output_mode: str = "external"
    output_files: tuple[str, ...] = ("chineseSubtitles",)

    @property
    def includes_video(self) -> bool:
        return "video" in self.output_files

    @property
    def requires_translation(self) -> bool:
        return any(
            output_file in {"video", "chineseSubtitles", "bilingualSubtitles"}
            for output_file in self.output_files
        )


@dataclass(frozen=True)
class Job:
    job_id: str
    input_kind: str
    audio_path: Path
    source_video_path: Path | None
    image_path: Path
    output_directory: Path
    working_directory: Path
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
        subtitle_output_mode = video.get("subtitleOutputMode", "external")

        return cls(
            job_id=str(payload["id"]),
            input_kind=str(payload.get("inputKind", "audio")),
            audio_path=Path(payload["audioPath"]),
            source_video_path=Path(payload["videoPath"]) if payload.get("videoPath") else None,
            image_path=Path(payload["imagePath"]),
            output_directory=Path(payload["outputDirectory"]),
            working_directory=Path(payload.get("workingDirectory", payload["outputDirectory"])),
            asr=ASRSettings(
                backend=asr["backend"],
                model=asr["model"],
                model_folder=asr.get("modelFolder", "Models/whisperkit"),
                device=asr["device"],
                compute_type=asr["computeType"],
                language=asr["language"],
                vad_enabled=bool(asr["vadEnabled"]),
                beam_size=int(asr["beamSize"]),
                cpu_threads=int(asr.get("cpuThreads", 8)),
            ),
            translation=_parse_translation_settings(translation),
            tools=ToolSettings(ffmpeg_path=Path(tools["ffmpegPath"])),
            video=VideoSettings(
                width=int(video["width"]),
                height=int(video["height"]),
                image_fit=video["imageFit"],
                background_color=video["backgroundColor"],
                subtitle_output_mode=subtitle_output_mode,
                output_files=_parse_output_files(video, subtitle_output_mode),
            ),
        )


def _parse_output_files(video: dict[str, Any], subtitle_output_mode: str) -> tuple[str, ...]:
    output_files = video.get("outputFiles")
    if output_files is None:
        if subtitle_output_mode == "external":
            return ("chineseSubtitles",)
        return ("video", "chineseSubtitles")

    known_outputs = ("video", "japaneseSubtitles", "chineseSubtitles", "bilingualSubtitles")
    normalized = tuple(output_file for output_file in known_outputs if output_file in output_files)
    if not normalized:
        raise ValueError("At least one output file must be selected.")
    return normalized


def _parse_translation_settings(translation: dict[str, Any]) -> TranslationSettings:
    if "selectedProvider" in translation:
        selected_provider = str(translation["selectedProvider"])
        provider_configurations = tuple(
            TranslationProviderConfiguration(
                provider=str(configuration["provider"]),
                base_url=str(configuration["baseURL"]),
                model=str(configuration["model"]),
            )
            for configuration in translation.get("providerConfigurations", [])
        )
    else:
        selected_provider = "openAICompatible"
        provider_configurations = (
            TranslationProviderConfiguration(
                provider=selected_provider,
                base_url=str(translation["endpoint"]),
                model=str(translation["model"]),
            ),
        )

    return TranslationSettings(
        backend=translation["backend"],
        selected_provider=selected_provider,
        provider_configurations=provider_configurations,
        prompt=translation["prompt"],
        timeout_seconds=int(translation["timeoutSeconds"]),
        retry_limit=int(translation["retryLimit"]),
    )
