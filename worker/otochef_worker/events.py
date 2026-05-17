from __future__ import annotations

import json
from typing import Any


def event_json(event_type: str, **fields: Any) -> str:
    payload = {"type": event_type}
    payload.update({key: value for key, value in fields.items() if value is not None})
    return json.dumps(payload, ensure_ascii=False)

