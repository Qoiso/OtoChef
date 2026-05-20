from __future__ import annotations

from dataclasses import dataclass
import textwrap


@dataclass(frozen=True)
class SubtitleSegment:
    segment_id: str
    start: float
    end: float
    text: str


def _srt_time(seconds: float) -> str:
    millis = round(seconds * 1000)
    hours, remainder = divmod(millis, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, ms = divmod(remainder, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02},{ms:03}"


def _ass_time(seconds: float) -> str:
    centis = round(seconds * 100)
    hours, remainder = divmod(centis, 360_000)
    minutes, remainder = divmod(remainder, 6_000)
    secs, cs = divmod(remainder, 100)
    return f"{hours}:{minutes:02}:{secs:02}.{cs:02}"


def _wrap_text(text: str, width: int = 24) -> str:
    lines: list[str] = []
    for raw_line in text.splitlines() or [text]:
        wrapped = textwrap.wrap(raw_line, width=width, break_long_words=False, replace_whitespace=False)
        lines.extend(wrapped or [raw_line])
    return "\n".join(lines)


def _escape_ass_text(text: str) -> str:
    return (
        text.replace("\\", "＼")
        .replace("{", "｛")
        .replace("}", "｝")
    )


def render_srt(segments: list[SubtitleSegment]) -> str:
    blocks: list[str] = []
    for index, segment in enumerate(segments, start=1):
        text = _wrap_text(segment.text)
        blocks.append(f"{index}\n{_srt_time(segment.start)} --> {_srt_time(segment.end)}\n{text}\n")
    return "\n".join(blocks)


def render_ass(segments: list[SubtitleSegment], width: int, height: int) -> str:
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Helvetica,54,&H00FFFFFF,&H00111111,&H80000000,0,0,0,0,100,100,0,0,1,3,1,2,80,80,64,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    lines = [header]
    for segment in segments:
        text = _wrap_text(_escape_ass_text(segment.text)).replace("\n", r"\N")
        lines.append(f"Dialogue: 0,{_ass_time(segment.start)},{_ass_time(segment.end)},Default,,0,0,0,,{text}\n")
    return "".join(lines)
