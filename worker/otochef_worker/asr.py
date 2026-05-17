from __future__ import annotations

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
