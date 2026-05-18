from pathlib import Path

from otochef_worker.ffmpeg import build_ffmpeg_command, ffprobe_path_for
from otochef_worker.models import VideoSettings


def test_build_ffmpeg_command_contains_static_image_audio_and_ass() -> None:
    command = build_ffmpeg_command(
        ffmpeg_path=Path("/usr/local/bin/ffmpeg"),
        image_path=Path("/tmp/image.png"),
        audio_path=Path("/tmp/audio.wav"),
        ass_path=Path("/tmp/subtitles.zh.ass"),
        srt_path=Path("/tmp/subtitles.zh.srt"),
        output_path=Path("/tmp/output.mp4"),
        video=VideoSettings(width=1920, height=1080, image_fit="contain", background_color="black"),
        burn_subtitles=True,
    )

    command_text = " ".join(command)

    assert command[:3] == ["/usr/local/bin/ffmpeg", "-y", "-loop"]
    assert "-framerate" in command
    assert "scale=w=1920:h=1080:force_original_aspect_ratio=decrease" in command_text
    assert "subtitles=filename=" in command_text
    assert command[-1] == "/tmp/output.mp4"


def test_build_ffmpeg_command_can_mux_soft_subtitles() -> None:
    command = build_ffmpeg_command(
        ffmpeg_path=Path("/usr/local/bin/ffmpeg"),
        image_path=Path("/tmp/image.png"),
        audio_path=Path("/tmp/audio.wav"),
        ass_path=Path("/tmp/subtitles.zh.ass"),
        srt_path=Path("/tmp/subtitles.zh.srt"),
        output_path=Path("/tmp/output.mp4"),
        video=VideoSettings(width=1920, height=1080, image_fit="contain", background_color="black"),
        burn_subtitles=False,
        duration_seconds=519.2,
    )

    command_text = " ".join(command)

    assert "/tmp/subtitles.zh.srt" in command
    assert "-c:s" in command
    assert "mov_text" in command
    assert "-t" in command
    assert "519.200" in command
    assert "subtitles=filename=" not in command_text


def test_ffprobe_path_for_replaces_ffmpeg_binary_name() -> None:
    assert ffprobe_path_for(Path("/opt/homebrew/bin/ffmpeg")) == Path("/opt/homebrew/bin/ffprobe")
