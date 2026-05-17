from otochef_worker.translation import TranscriptSegment, build_translation_payload, parse_translation_response


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
