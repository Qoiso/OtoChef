import json

import pytest
import requests

from otochef_worker.models import TranslationProviderConfiguration, TranslationSettings
from otochef_worker.translation import (
    RoutedTranslationProvider,
    TranscriptSegment,
    build_translation_payload,
    describe_translation_plan,
    parse_translation_response,
)


def test_build_translation_payload_preserves_segment_ids() -> None:
    segments = [
        TranscriptSegment(segment_id="s1", start=0.0, end=1.0, text="こんにちは"),
        TranscriptSegment(segment_id="s2", start=1.0, end=2.0, text="世界"),
    ]

    payload = build_translation_payload(segments)

    assert payload == [
        {"id": "s1", "text": "こんにちは"},
        {"id": "s2", "text": "世界"},
    ]


def test_parse_translation_response_reads_json_array() -> None:
    content = '[{"id":"s1","text":"你好"},{"id":"s2","text":"世界"}]'

    translations = parse_translation_response(content)

    assert translations == {"s1": "你好", "s2": "世界"}


def test_parse_translation_response_accepts_common_translation_field_alias() -> None:
    content = '[{"id":"s1","translation":"你好"}]'

    translations = parse_translation_response(content)

    assert translations == {"s1": "你好"}


def test_parse_translation_response_reports_missing_text_with_segment_id() -> None:
    content = '[{"id":"s1","value":"你好"}]'

    try:
        parse_translation_response(content)
    except ValueError as error:
        assert "s1" in str(error)
        assert "text" in str(error)
    else:
        raise AssertionError("Expected missing text to raise ValueError")


def test_parse_translation_response_rejects_duplicate_ids() -> None:
    content = '[{"id":"s1","text":"你好"},{"id":"s1","text":"重复"}]'

    with pytest.raises(ValueError, match="Duplicate translation id: s1"):
        parse_translation_response(content)


def test_openai_compatible_provider_posts_to_chat_completions(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": '[{"id":"s1","text":"你好"}]'}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="deepSeek",
        provider_configurations=(
            TranslationProviderConfiguration("deepSeek", "https://api.deepseek.com", "deepseek-v4-flash"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )

    result = RoutedTranslationProvider(settings, api_key="secret").translate(
        [TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")]
    )

    assert result == {"s1": "你好"}
    assert calls[0][0] == "https://api.deepseek.com/chat/completions"
    assert calls[0][1]["headers"]["Authorization"] == "Bearer secret"
    assert calls[0][1]["json"]["model"] == "deepseek-v4-flash"
    assert calls[0][1]["json"]["thinking"] == {"type": "disabled"}
    assert calls[0][1]["json"]["response_format"] == {"type": "json_object"}
    assert "Return only valid JSON" in calls[0][1]["json"]["messages"][0]["content"]
    assert "translations" in calls[0][1]["json"]["messages"][0]["content"]


def test_openai_compatible_provider_does_not_add_deepseek_options_to_other_providers(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": '[{"id":"s1","text":"你好"}]'}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="openAICompatible",
        provider_configurations=(
            TranslationProviderConfiguration("openAICompatible", "https://api.example.com/v1", "model-name"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )

    RoutedTranslationProvider(settings, api_key="secret").translate(
        [TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")]
    )

    assert "thinking" not in calls[0][1]["json"]
    assert "response_format" not in calls[0][1]["json"]


def test_openai_compatible_provider_retries_transient_request_failures(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": '[{"id":"s1","text":"你好"}]'}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        if len(calls) == 1:
            raise requests.Timeout("slow")
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="openAICompatible",
        provider_configurations=(
            TranslationProviderConfiguration("openAICompatible", "https://api.example.com/v1", "model-name"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=1,
    )

    result = RoutedTranslationProvider(settings, api_key="secret").translate(
        [TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")]
    )

    assert result == {"s1": "你好"}
    assert len(calls) == 2


def test_remote_provider_keeps_large_payload_in_one_request_for_context(monkeypatch) -> None:
    calls = []

    class Response:
        def __init__(self, request_json: dict):
            user_payload = json.loads(request_json["messages"][1]["content"])
            self.content = json.dumps(
                {"translations": [{"id": item["id"], "text": f"译文-{item['id']}"} for item in user_payload]},
                ensure_ascii=False,
            )

        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"choices": [{"message": {"content": self.content}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response(kwargs["json"])

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="deepSeek",
        provider_configurations=(
            TranslationProviderConfiguration("deepSeek", "https://api.deepseek.com", "deepseek-v4-flash"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )
    segments = [
        TranscriptSegment(segment_id=f"seg-{index:04d}", start=index, end=index + 1, text="こんにちは")
        for index in range(65)
    ]

    result = RoutedTranslationProvider(settings, api_key="secret").translate(segments)

    assert len(calls) == 1
    user_payload = json.loads(calls[0][1]["json"]["messages"][1]["content"])
    assert len(user_payload) == 65
    assert result["seg-0000"] == "译文-seg-0000"
    assert result["seg-0064"] == "译文-seg-0064"


def test_describe_translation_plan_reports_single_context_request_for_large_remote_jobs() -> None:
    settings = TranslationSettings(
        backend="api",
        selected_provider="deepSeek",
        provider_configurations=(
            TranslationProviderConfiguration("deepSeek", "https://api.deepseek.com", "deepseek-v4-flash"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )
    segments = [
        TranscriptSegment(segment_id=f"seg-{index:04d}", start=index, end=index + 1, text="こんにちは")
        for index in range(65)
    ]

    assert describe_translation_plan(settings, segments) == "正在翻译中文字幕（65 段，保持上下文）"


def test_claude_provider_posts_to_messages_api(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"content": [{"type": "text", "text": '[{"id":"s1","text":"你好"}]'}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="claude",
        provider_configurations=(
            TranslationProviderConfiguration("claude", "https://api.anthropic.com", "claude-sonnet-4-5-20250929"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )

    result = RoutedTranslationProvider(settings, api_key="secret").translate(
        [TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")]
    )

    assert result == {"s1": "你好"}
    assert calls[0][0] == "https://api.anthropic.com/v1/messages"
    assert calls[0][1]["headers"]["x-api-key"] == "secret"
    assert calls[0][1]["headers"]["anthropic-version"] == "2023-06-01"
    assert calls[0][1]["json"]["system"].startswith("Translate")
    assert "Return only valid JSON" in calls[0][1]["json"]["system"]
    assert calls[0][1]["json"]["model"] == "claude-sonnet-4-5-20250929"
    assert calls[0][1]["json"]["max_tokens"] == 4096


def test_gemini_provider_posts_to_generate_content(monkeypatch) -> None:
    calls = []

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict:
            return {"candidates": [{"content": {"parts": [{"text": '[{"id":"s1","text":"你好"}]'}]}}]}

    def fake_post(url, **kwargs):
        calls.append((url, kwargs))
        return Response()

    monkeypatch.setattr("otochef_worker.translation.requests.post", fake_post)
    settings = TranslationSettings(
        backend="api",
        selected_provider="gemini",
        provider_configurations=(
            TranslationProviderConfiguration("gemini", "https://generativelanguage.googleapis.com", "gemini-2.0-flash"),
        ),
        prompt="Translate",
        timeout_seconds=120,
        retry_limit=2,
    )

    result = RoutedTranslationProvider(settings, api_key="secret").translate(
        [TranscriptSegment(segment_id="s1", start=0, end=1, text="こんにちは")]
    )

    assert result == {"s1": "你好"}
    assert calls[0][0] == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
    assert calls[0][1]["params"] == {"key": "secret"}
    system_text = calls[0][1]["json"]["systemInstruction"]["parts"][0]["text"]
    assert system_text.startswith("Translate")
    assert "Return only valid JSON" in system_text
    assert calls[0][1]["json"]["generationConfig"]["temperature"] == 0.2
