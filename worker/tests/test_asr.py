from types import SimpleNamespace

from otochef_worker.asr import segments_from_faster_whisper


def test_segments_from_faster_whisper_assigns_stable_ids() -> None:
    raw_segments = [
        SimpleNamespace(start=0.0, end=1.25, text=" こんにちは "),
        SimpleNamespace(start=1.25, end=2.5, text="世界"),
    ]

    segments = segments_from_faster_whisper(raw_segments)

    assert [segment.segment_id for segment in segments] == ["seg-0001", "seg-0002"]
    assert segments[0].text == "こんにちは"
    assert segments[1].start == 1.25
