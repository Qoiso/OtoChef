from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Iterable, Protocol

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


def resolve_model_reference(model: str, search_roots: Iterable[Path] | None = None) -> str:
    model_path = Path(model).expanduser()
    if model_path.exists():
        return str(model_path)

    roots = list(search_roots or [])
    for env_name in ("OTOCHEF_MODEL_ROOT", "OTOCHEF_PROJECT_ROOT", "OTOCHEF_OUTPUT_ROOT"):
        if value := os.environ.get(env_name):
            roots.append(Path(value))

    roots.extend([Path.cwd(), Path.cwd().parent, Path.cwd().parent.parent])

    repo_colon_name = model.replace("/", ":")
    repo_nested_parts = model.split("/")
    candidates: list[Path] = []
    for root in roots:
        candidates.extend(
            [
                root / model,
                root / repo_colon_name,
                root / "Models" / repo_colon_name,
                root / "models" / repo_colon_name,
                root / "Sources" / "OtoChefApp" / "Models" / repo_colon_name,
            ]
        )
        if len(repo_nested_parts) > 1:
            nested = Path(*repo_nested_parts)
            candidates.extend(
                [
                    root / nested,
                    root / "Models" / nested,
                    root / "models" / nested,
                    root / "Sources" / "OtoChefApp" / "Models" / nested,
                ]
            )

    seen: set[Path] = set()
    for candidate in candidates:
        candidate = candidate.expanduser()
        if candidate in seen:
            continue
        seen.add(candidate)
        if candidate.is_dir() and ((candidate / "model.bin").exists() or (candidate / "config.json").exists()):
            return str(candidate)

    return model


class FasterWhisperASRProvider:
    def __init__(self, settings: ASRSettings, search_roots: Iterable[Path] | None = None):
        self.settings = settings
        self.search_roots = list(search_roots or [])

    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        from faster_whisper import WhisperModel

        device = "auto" if self.settings.device == "auto" else self.settings.device
        compute_type = "default" if self.settings.compute_type == "auto" else self.settings.compute_type
        model_reference = resolve_model_reference(self.settings.model, self.search_roots)
        model = WhisperModel(model_reference, device=device, compute_type=compute_type)
        raw_segments, _info = model.transcribe(
            str(audio_path),
            language=self.settings.language,
            beam_size=self.settings.beam_size,
            vad_filter=self.settings.vad_enabled,
        )
        return segments_from_faster_whisper(raw_segments)
