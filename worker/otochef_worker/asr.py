from __future__ import annotations

from pathlib import Path
from typing import Protocol

from .translation import TranscriptSegment


class ASRProvider(Protocol):
    def transcribe(self, audio_path: Path) -> list[TranscriptSegment]:
        raise NotImplementedError
