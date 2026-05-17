from __future__ import annotations

from pathlib import Path
import subprocess

from .models import VideoSettings


def build_ffmpeg_command(
    ffmpeg_path: Path,
    image_path: Path,
    audio_path: Path,
    ass_path: Path,
    output_path: Path,
    video: VideoSettings,
) -> list[str]:
    if video.image_fit == "contain":
        scale = (
            f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=decrease,"
            f"pad={video.width}:{video.height}:(ow-iw)/2:(oh-ih)/2:color={video.background_color}"
        )
    else:
        scale = (
            f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=increase,"
            f"crop={video.width}:{video.height}"
        )

    video_filter = f"{scale},subtitles={ass_path}"
    return [
        str(ffmpeg_path),
        "-y",
        "-loop",
        "1",
        "-i",
        str(image_path),
        "-i",
        str(audio_path),
        "-vf",
        video_filter,
        "-c:v",
        "libx264",
        "-tune",
        "stillimage",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
        "-pix_fmt",
        "yuv420p",
        "-shortest",
        str(output_path),
    ]


def run_ffmpeg(command: list[str]) -> None:
    subprocess.run(command, check=True, text=True, capture_output=True)
