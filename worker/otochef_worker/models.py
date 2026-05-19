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
                subtitle_output_mode=video.get("subtitleOutputMode", "external"),
            ),
        )


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
