from types import SimpleNamespace

from otochef_worker.asr import effective_runtime_options, resolve_model_reference, segments_from_faster_whisper
from otochef_worker.models import ASRSettings


def test_segments_from_faster_whisper_assigns_stable_ids() -> None:
    raw_segments = [
        SimpleNamespace(start=0.0, end=1.25, text=" こんにちは "),
        SimpleNamespace(start=1.25, end=2.5, text="世界"),
    ]

    segments = segments_from_faster_whisper(raw_segments)

    assert [segment.segment_id for segment in segments] == ["seg-0001", "seg-0002"]
    assert segments[0].text == "こんにちは"
    assert segments[1].start == 1.25


def test_resolve_model_reference_prefers_local_repo_id_directory(tmp_path) -> None:
    local_model = tmp_path / "Models" / "Systran:faster-whisper-large-v3"
    local_model.mkdir(parents=True)
    (local_model / "model.bin").write_text("fake", encoding="utf-8")

    resolved = resolve_model_reference("Systran/faster-whisper-large-v3", search_roots=[tmp_path])

    assert resolved == str(local_model)


def test_resolve_model_reference_keeps_repo_id_when_no_local_directory(tmp_path) -> None:
    resolved = resolve_model_reference("Example/not-present", search_roots=[tmp_path])

    assert resolved == "Example/not-present"


def test_effective_runtime_options_prefers_cpu_int8_for_auto_settings() -> None:
    settings = ASRSettings(
        backend="fasterWhisper",
        model="Systran/faster-whisper-large-v3",
        device="auto",
        compute_type="auto",
        language="ja",
        vad_enabled=True,
        beam_size=5,
        cpu_threads=8,
    )

    device, compute_type = effective_runtime_options(settings)

    assert device == "cpu"
    assert compute_type == "int8"
