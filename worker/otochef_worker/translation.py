from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Protocol

import requests

from .models import TranslationSettings


@dataclass(frozen=True)
class TranscriptSegment:
    segment_id: str
    start: float
    end: float
    text: str


class TranslationProvider(Protocol):
    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        raise NotImplementedError


def build_translation_payload(segments: list[TranscriptSegment]) -> list[dict[str, str]]:
    return [{"id": segment.segment_id, "text": segment.text} for segment in segments]


def parse_translation_response(content: str) -> dict[str, str]:
    payload = json.loads(content)
    if not isinstance(payload, list):
        raise ValueError("Translation response must be a JSON array")
    result: dict[str, str] = {}
    for item in payload:
        result[str(item["id"])] = str(item["text"])
    return result


class OpenAICompatibleTranslationProvider:
    def __init__(self, settings: TranslationSettings, api_key: str | None = None):
        self.settings = settings
        self.api_key = api_key

    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        user_payload = json.dumps(build_translation_payload(segments), ensure_ascii=False)
        response = requests.post(
            f"{self.settings.endpoint.rstrip('/')}/chat/completions",
            headers=headers,
            timeout=self.settings.timeout_seconds,
            json={
                "model": self.settings.model,
                "messages": [
                    {"role": "system", "content": self.settings.prompt},
                    {"role": "user", "content": user_payload},
                ],
                "temperature": 0.2,
            },
        )
        response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
        return parse_translation_response(content)
