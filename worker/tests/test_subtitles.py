from otochef_worker.subtitles import SubtitleSegment, render_ass, render_srt


def test_render_srt_formats_times_and_text() -> None:
    segments = [SubtitleSegment(segment_id="s1", start=1.2, end=3.45, text="你好，世界")]

    srt = render_srt(segments)

    assert "1\n00:00:01,200 --> 00:00:03,450\n你好，世界\n" in srt


def test_render_ass_escapes_newlines() -> None:
    segments = [SubtitleSegment(segment_id="s1", start=0.0, end=2.0, text="第一行\n第二行")]

    ass = render_ass(segments, width=1920, height=1080)

    assert "PlayResX: 1920" in ass
    assert "Dialogue: 0,0:00:00.00,0:00:02.00,Default,,0,0,0,,第一行\\N第二行" in ass
