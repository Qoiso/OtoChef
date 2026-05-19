from __future__ import annotations

from dataclasses import dataclass
import json
import re
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
    payload = json.loads(_strip_json_code_fence(content))
    if isinstance(payload, dict) and isinstance(payload.get("translations"), list):
        payload = payload["translations"]
    if not isinstance(payload, list):
        raise ValueError("Translation response must be a JSON array")
    result: dict[str, str] = {}
    for item in payload:
        if not isinstance(item, dict):
            raise ValueError("Each translation item must be a JSON object")
        segment_id = item.get("id")
        if segment_id is None:
            raise ValueError(f"Translation item is missing id: {item}")
        translated = item.get("text", item.get("translation", item.get("translatedText")))
        if translated is None:
            raise ValueError(f"Translation item for id {segment_id} is missing text")
        result[str(segment_id)] = str(translated)
    return result


class OpenAICompatibleTranslationProvider:
    def __init__(self, settings: TranslationSettings, api_key: str | None = None):
        self.settings = settings
        self.api_key = api_key

    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        configuration = self.settings.active_configuration
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        user_payload = json.dumps(build_translation_payload(segments), ensure_ascii=False)
        uses_deepseek_json_object = self.settings.selected_provider == "deepSeek"
        request_body = {
            "model": configuration.model,
            "messages": [
                {
                    "role": "system",
                    "content": _format_instructions(
                        self.settings.prompt,
                        json_object=uses_deepseek_json_object,
                    ),
                },
                {"role": "user", "content": user_payload},
            ],
            "temperature": 0.2,
        }
        if uses_deepseek_json_object:
            request_body["thinking"] = {"type": "disabled"}
            request_body["response_format"] = {"type": "json_object"}

        response = requests.post(
            f"{configuration.base_url.rstrip('/')}/chat/completions",
            headers=headers,
            timeout=self.settings.timeout_seconds,
            json=request_body,
        )
        response.raise_for_status()
        content = response.json()["choices"][0]["message"]["content"]
        return parse_translation_response(content)


OPENAI_COMPATIBLE_PROVIDERS = {"deepSeek", "openAI", "ollama", "lmStudio", "openAICompatible"}


class RoutedTranslationProvider:
    def __init__(self, settings: TranslationSettings, api_key: str | None = None):
        self.settings = settings
        self.api_key = api_key

    def translate(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        if self.settings.selected_provider in OPENAI_COMPATIBLE_PROVIDERS:
            return self._translate_openai_compatible(segments)
        if self.settings.selected_provider == "claude":
            return self._translate_claude(segments)
        if self.settings.selected_provider == "gemini":
            return self._translate_gemini(segments)
        raise ValueError(f"Unsupported translation provider: {self.settings.selected_provider}")

    def _translate_openai_compatible(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        return OpenAICompatibleTranslationProvider(self.settings, self.api_key).translate(segments)

    def _translate_claude(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        configuration = self.settings.active_configuration
        headers = {
            "Content-Type": "application/json",
            "x-api-key": self.api_key or "",
            "anthropic-version": "2023-06-01",
        }
        user_payload = json.dumps(build_translation_payload(segments), ensure_ascii=False)
        response = requests.post(
            f"{configuration.base_url.rstrip('/')}/v1/messages",
            headers=headers,
            timeout=self.settings.timeout_seconds,
            json={
                "model": configuration.model,
                "system": _format_instructions(self.settings.prompt),
                "messages": [{"role": "user", "content": user_payload}],
                "max_tokens": 4096,
                "temperature": 0.2,
            },
        )
        response.raise_for_status()
        content = _first_text_block(response.json()["content"])
        return parse_translation_response(content)

    def _translate_gemini(self, segments: list[TranscriptSegment]) -> dict[str, str]:
        configuration = self.settings.active_configuration
        user_payload = json.dumps(build_translation_payload(segments), ensure_ascii=False)
        response = requests.post(
            f"{configuration.base_url.rstrip('/')}/v1beta/models/{configuration.model}:generateContent",
            params={"key": self.api_key or ""},
            headers={"Content-Type": "application/json"},
            timeout=self.settings.timeout_seconds,
            json={
                "systemInstruction": {"parts": [{"text": _format_instructions(self.settings.prompt)}]},
                "contents": [{"role": "user", "parts": [{"text": user_payload}]}],
                "generationConfig": {"temperature": 0.2},
            },
        )
        response.raise_for_status()
        parts = response.json()["candidates"][0]["content"]["parts"]
        return parse_translation_response(_first_text_block(parts))


def _first_text_block(blocks: list[dict[str, object]]) -> str:
    for block in blocks:
        text = block.get("text")
        if isinstance(text, str):
            return text
    raise ValueError("Translation response did not contain text")


def _format_instructions(prompt: str, *, json_object: bool = False) -> str:
    if json_object:
        return (
            f"{prompt.strip()}\n\n"
            "Return only valid JSON. The JSON must be an object with one key named translations. "
            'translations must be an array of objects shaped like {"id":"seg-0001","text":"简体中文翻译"}. '
            "Do not include Markdown fences, explanations, or any keys other than translations, id, and text."
        )
    return (
        f"{prompt.strip()}\n\n"
        "Return only valid JSON. The JSON must be an array. "
        'Each item must have exactly this shape: {"id":"seg-0001","text":"简体中文翻译"}. '
        "Do not include Markdown fences, explanations, or any keys other than id and text."
    )


def _strip_json_code_fence(content: str) -> str:
    stripped = content.strip()
    match = re.fullmatch(r"```(?:json)?\s*(.*?)\s*```", stripped, flags=re.DOTALL)
    if match:
        return match.group(1).strip()
    return stripped


def describe_translation_plan(settings: TranslationSettings, segments: list[TranscriptSegment]) -> str:
    segment_count = len(segments)
    return f"正在翻译中文字幕（{segment_count} 段，保持上下文）"
