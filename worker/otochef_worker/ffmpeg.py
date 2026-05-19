from __future__ import annotations

from pathlib import Path
import subprocess

from .models import VideoSettings


def ffprobe_path_for(ffmpeg_path: Path) -> Path:
    if ffmpeg_path.name == "ffmpeg":
        return ffmpeg_path.with_name("ffprobe")
    return Path("ffprobe")


def probe_media_duration(ffmpeg_path: Path, media_path: Path) -> float:
    ffprobe_path = ffprobe_path_for(ffmpeg_path)
    result = subprocess.run(
        [
            str(ffprobe_path),
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(media_path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    return float(result.stdout.strip())


def ffmpeg_supports_filter(ffmpeg_path: Path, filter_name: str) -> bool:
    result = subprocess.run(
        [str(ffmpeg_path), "-hide_banner", "-filters"],
        check=True,
        capture_output=True,
        text=True,
    )
    return any(
        parts[1] == filter_name
        for line in result.stdout.splitlines()
        if len(parts := line.split()) >= 2
    )


def _escape_filter_path(path: Path) -> str:
    text = str(path)
    return text.replace("\\", "\\\\").replace("'", "\\'").replace(":", "\\:")


def _base_video_filter(video: VideoSettings) -> str:
    if video.image_fit == "contain":
        return (
            f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=decrease,"
            f"pad={video.width}:{video.height}:(ow-iw)/2:(oh-ih)/2:color={video.background_color}"
        )
    return (
        f"scale=w={video.width}:h={video.height}:force_original_aspect_ratio=increase,"
        f"crop={video.width}:{video.height}"
    )


def _base_image_audio_command(ffmpeg_path: Path, image_path: Path, audio_path: Path) -> list[str]:
    return [
        str(ffmpeg_path),
        "-y",
        "-loop",
        "1",
        "-framerate",
        "1",
        "-i",
        str(image_path),
        "-i",
        str(audio_path),
    ]


def build_hard_subtitle_mp4_command(
    ffmpeg_path: Path,
    image_path: Path,
    audio_path: Path,
    ass_path: Path,
    output_path: Path,
    video: VideoSettings,
    duration_seconds: float | None = None,
) -> list[str]:
    scale = _base_video_filter(video)
    video_filter = f"{scale},subtitles=filename='{_escape_filter_path(ass_path)}'"
    command = _base_image_audio_command(ffmpeg_path, image_path, audio_path)
    command.extend(["-vf", video_filter])
    command.extend(_shared_video_audio_encoding_args())
    if duration_seconds is not None:
        command.extend(["-t", f"{duration_seconds:.3f}"])
    else:
        command.append("-shortest")

    command.append(str(output_path))
    return command


def build_soft_subtitle_mkv_command(
    ffmpeg_path: Path,
    image_path: Path,
    audio_path: Path,
    ass_path: Path,
    output_path: Path,
    video: VideoSettings,
    duration_seconds: float,
) -> list[str]:
    command = _base_image_audio_command(ffmpeg_path, image_path, audio_path)
    command.extend(["-i", str(ass_path)])
    command.extend(["-vf", _base_video_filter(video)])
    command.extend(["-map", "0:v:0", "-map", "1:a:0", "-map", "2:s:0"])
    command.extend(_shared_video_audio_encoding_args())
    command.extend(["-c:s", "ass", "-metadata:s:s:0", "language=chi"])
    command.extend(["-pix_fmt", "yuv420p", "-t", f"{duration_seconds:.3f}", str(output_path)])
    return command


def _shared_video_audio_encoding_args() -> list[str]:
    return [
        "-c:v",
        "libx264",
        "-tune",
        "stillimage",
        "-r",
        "1",
        "-c:a",
        "aac",
        "-b:a",
        "192k",
    ]


def build_ffmpeg_command(
    ffmpeg_path: Path,
    image_path: Path,
    audio_path: Path,
    ass_path: Path,
    srt_path: Path,
    output_path: Path,
    video: VideoSettings,
    burn_subtitles: bool = True,
    duration_seconds: float | None = None,
) -> list[str]:
    if burn_subtitles:
        return build_hard_subtitle_mp4_command(
            ffmpeg_path=ffmpeg_path,
            image_path=image_path,
            audio_path=audio_path,
            ass_path=ass_path,
            output_path=output_path,
            video=video,
            duration_seconds=duration_seconds,
        )
    command = _base_image_audio_command(ffmpeg_path, image_path, audio_path)
    command.extend(["-i", str(srt_path)])
    command.extend(["-vf", _base_video_filter(video)])
    command.extend(["-map", "0:v:0", "-map", "1:a:0", "-map", "2:s:0"])
    command.extend(_shared_video_audio_encoding_args())
    command.extend(["-c:s", "mov_text", "-metadata:s:s:0", "language=chi"])
    command.extend(["-pix_fmt", "yuv420p"])
    if duration_seconds is not None:
        command.extend(["-t", f"{duration_seconds:.3f}"])
    else:
        command.append("-shortest")
    command.append(str(output_path))
    return command


def run_ffmpeg(command: list[str]) -> None:
    try:
        subprocess.run(command, check=True, text=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        details = (error.stderr or error.stdout or str(error)).strip()
        raise RuntimeError(f"FFmpeg failed: {details[-4000:]}") from error
