from pathlib import Path

from otochef_worker.ffmpeg import build_ffmpeg_command
from otochef_worker.models import VideoSettings


def test_build_ffmpeg_command_contains_static_image_audio_and_ass() -> None:
    command = build_ffmpeg_command(
        ffmpeg_path=Path("/usr/local/bin/ffmpeg"),
        image_path=Path("/tmp/image.png"),
        audio_path=Path("/tmp/audio.wav"),
        ass_path=Path("/tmp/subtitles.zh.ass"),
        output_path=Path("/tmp/output.mp4"),
        video=VideoSettings(width=1920, height=1080, image_fit="contain", background_color="black"),
    )

    command_text = " ".join(command)

    assert command[:3] == ["/usr/local/bin/ffmpeg", "-y", "-loop"]
    assert "scale=w=1920:h=1080:force_original_aspect_ratio=decrease" in command_text
    assert "subtitles=/tmp/subtitles.zh.ass" in command_text
    assert command[-1] == "/tmp/output.mp4"
