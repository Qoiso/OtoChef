import json

from otochef_worker.events import event_json


def test_event_json_uses_worker_event_shape() -> None:
    line = event_json("stage_started", stage="asr", message="Transcribing audio")

    payload = json.loads(line)

    assert payload == {
        "type": "stage_started",
        "stage": "asr",
        "message": "Transcribing audio",
    }
