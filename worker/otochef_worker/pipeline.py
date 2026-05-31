from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import tempfile
import time
from typing import Callable

from .asr import ASRProvider
from .ffmpeg import (
    build_hard_subtitle_mp4_command,
    build_hard_subtitle_source_video_mp4_command,
    build_soft_subtitle_mkv_command,
    build_soft_subtitle_source_video_mkv_command,
    ffmpeg_supports_filter,
    probe_media_duration,
    run_ffmpeg,
)
from .models import Job
from .subtitles import SubtitleSegment, render_ass, render_srt
from .translation import RoutedTranslationProvider, TranscriptSegment, TranslationProvider, describe_translation_plan


PipelineEventEmitter = Callable[..., None]


@dataclass(frozen=True)
class PipelineArtifacts:
    transcript_path: Path
    translation_path: Path | None
    srt_path: Path | None
    ass_path: Path | None
    subtitle_paths: tuple[Path, ...]
    output_video_path: Path | None


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def _read_transcript_segments(path: Path) -> list[TranscriptSegment]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return [
        TranscriptSegment(
            segment_id=str(segment["id"]),
            start=float(segment["start"]),
            end=float(segment["end"]),
            text=_clean_transcript_text(str(segment["text"])),
        )
        for segment in payload.get("segments", [])
        if _clean_transcript_text(str(segment.get("text", "")))
    ]


def _clean_transcript_text(text: str) -> str:
    return re.sub(r"<\|[^|]+?\|>", "", text).strip()


def _validated_translations(
    segments: list[TranscriptSegment],
    translated_text: dict[str, str],
) -> dict[str, str]:
    expected_ids = [segment.segment_id for segment in segments]
    expected = set(expected_ids)
    actual = set(translated_text)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    problems: list[str] = []
    if missing:
        problems.append(f"missing translations for: {', '.join(missing)}")
    if extra:
        problems.append(f"unexpected translations for: {', '.join(extra)}")
    if problems:
        raise ValueError("; ".join(problems))
    return translated_text


def _transcript_subtitle_segments(segments: list[TranscriptSegment]) -> list[SubtitleSegment]:
    return [
        SubtitleSegment(
            segment_id=segment.segment_id,
            start=segment.start,
            end=segment.end,
            text=segment.text,
        )
        for segment in segments
    ]


def _translated_subtitle_segments(
    segments: list[TranscriptSegment],
    translated_text: dict[str, str],
) -> list[SubtitleSegment]:
    return [
        SubtitleSegment(
            segment_id=segment.segment_id,
            start=segment.start,
            end=segment.end,
            text=translated_text[segment.segment_id],
        )
        for segment in segments
    ]


def _bilingual_subtitle_segments(
    segments: list[TranscriptSegment],
    translated_text: dict[str, str],
) -> list[SubtitleSegment]:
    return [
        SubtitleSegment(
            segment_id=segment.segment_id,
            start=segment.start,
            end=segment.end,
            text=f"{segment.text}\n{translated_text[segment.segment_id]}",
        )
        for segment in segments
    ]


def _write_subtitle_files(
    output_directory: Path,
    stem: str,
    segments: list[SubtitleSegment],
    width: int,
    height: int,
    emit: PipelineEventEmitter | None,
    label: str,
) -> tuple[Path, Path]:
    srt_path = output_directory / f"{stem}.srt"
    ass_path = output_directory / f"{stem}.ass"
    srt_path.write_text(render_srt(segments), encoding="utf-8")
    ass_path.write_text(render_ass(segments, width=width, height=height), encoding="utf-8")
    if emit:
        emit("artifact_created", stage="subtitle", message=f"{label} SRT 已生成", progress=0.78, path=str(srt_path))
        emit("artifact_created", stage="subtitle", message=f"{label} ASS 已生成", progress=0.82, path=str(ass_path))
    return srt_path, ass_path


def run_pipeline(
    job: Job,
    asr: ASRProvider | None = None,
    translator: TranslationProvider | None = None,
    run_video: bool = True,
    emit: PipelineEventEmitter | None = None,
) -> PipelineArtifacts:
    job.output_directory.mkdir(parents=True, exist_ok=True)
    job.working_directory.mkdir(parents=True, exist_ok=True)
    asr_provider = asr

    transcript_path = job.working_directory / "transcript.ja.json"
    if transcript_path.exists():
        transcript_segments = _read_transcript_segments(transcript_path)
    else:
        if emit:
            emit("stage_started", stage="asr", message="正在加载 ASR 模型并识别日语音频", progress=0.05)
        if asr_provider is None:
            raise RuntimeError("WhisperKit transcript.ja.json is missing; run the macOS app native ASR step first.")
        transcript_segments = asr_provider.transcribe(job.audio_path)
        _write_json(
            transcript_path,
            {
                "segments": [
                    {
                        "id": segment.segment_id,
                        "start": segment.start,
                        "end": segment.end,
                        "text": segment.text,
                    }
                    for segment in transcript_segments
                ]
            },
        )
    if emit:
        emit("artifact_created", stage="asr", message="日语转写已完成", progress=0.40, path=str(transcript_path))

    translated_text: dict[str, str] | None = None
    translation_path: Path | None = None
    if job.video.requires_translation:
        translation_provider = translator or RoutedTranslationProvider(
            job.translation,
            api_key=os.environ.get("OTOCHEF_TRANSLATION_API_KEY"),
        )
        if emit:
            emit(
                "stage_started",
                stage="translation",
                message=describe_translation_plan(job.translation, transcript_segments),
                progress=0.45,
            )
        translation_started_at = time.perf_counter()
        translated_text = _validated_translations(
            transcript_segments,
            translation_provider.translate(transcript_segments),
        )
        translation_elapsed = time.perf_counter() - translation_started_at
        if emit:
            emit(
                "progress",
                stage="translation",
                message=f"翻译请求完成，用时 {translation_elapsed:.1f} 秒",
                progress=0.62,
            )
        translated_segments = _translated_subtitle_segments(transcript_segments, translated_text)
        translation_path = job.working_directory / "translation.zh.json"
        _write_json(
            translation_path,
            {
                "segments": [
                    {
                        "id": segment.segment_id,
                        "start": segment.start,
                        "end": segment.end,
                        "text": segment.text,
                    }
                    for segment in translated_segments
                ]
            },
        )
        if emit:
            emit("artifact_created", stage="translation", message="中文字幕翻译已完成", progress=0.65, path=str(translation_path))

    subtitle_paths: list[Path] = []
    chinese_ass_path: Path | None = None
    bilingual_ass_path: Path | None = None
    srt_path: Path | None = None
    ass_path: Path | None = None
    visible_subtitle_outputs = [
        output_file
        for output_file in ("japaneseSubtitles", "chineseSubtitles", "bilingualSubtitles")
        if output_file in job.video.output_files
    ]
    if visible_subtitle_outputs:
        if emit:
            emit("stage_started", stage="subtitle", message="正在生成字幕文件", progress=0.70)
        for output_file in visible_subtitle_outputs:
            if output_file == "japaneseSubtitles":
                source_stem = "subtitles.source" if job.input_kind == "video" else "subtitles.ja"
                source_label = "原文字幕" if job.input_kind == "video" else "日语字幕"
                generated = _write_subtitle_files(
                    job.output_directory,
                    source_stem,
                    _transcript_subtitle_segments(transcript_segments),
                    job.video.width,
                    job.video.height,
                    emit,
                    source_label,
                )
            elif output_file == "chineseSubtitles":
                assert translated_text is not None
                generated = _write_subtitle_files(
                    job.output_directory,
                    "subtitles.zh",
                    _translated_subtitle_segments(transcript_segments, translated_text),
                    job.video.width,
                    job.video.height,
                    emit,
                    "中文字幕",
                )
                chinese_ass_path = generated[1]
                srt_path, ass_path = generated
            else:
                assert translated_text is not None
                bilingual_stem = "subtitles.source-zh" if job.input_kind == "video" else "subtitles.ja-zh"
                generated = _write_subtitle_files(
                    job.output_directory,
                    bilingual_stem,
                    _bilingual_subtitle_segments(transcript_segments, translated_text),
                    job.video.width,
                    job.video.height,
                    emit,
                    "双语字幕",
                )
                bilingual_ass_path = generated[1]
            subtitle_paths.extend(generated)

    output_video_path: Path | None = None
    subtitle_mode = job.video.subtitle_output_mode
    if run_video and job.video.includes_video:
        if translated_text is None:
            raise RuntimeError("视频输出需要先完成中文字幕翻译。")
        if emit:
            emit("stage_started", stage="ffmpeg", message="正在调用 FFmpeg 合成视频", progress=0.86)
        temp_dir: tempfile.TemporaryDirectory[str] | None = None
        video_ass_path = bilingual_ass_path or chinese_ass_path
        if video_ass_path is None:
            temp_dir = tempfile.TemporaryDirectory()
            video_ass_path = Path(temp_dir.name) / "video-subtitles.ass"
            video_ass_path.write_text(
                render_ass(
                    _translated_subtitle_segments(transcript_segments, translated_text),
                    width=job.video.width,
                    height=job.video.height,
                ),
                encoding="utf-8",
            )
        if subtitle_mode == "mkvSoftAss":
            output_video_path = job.output_directory / "output.mkv"
            if job.input_kind == "video":
                if job.source_video_path is None:
                    raise RuntimeError("视频任务缺少源视频路径。")
                command = build_soft_subtitle_source_video_mkv_command(
                    ffmpeg_path=job.tools.ffmpeg_path,
                    video_path=job.source_video_path,
                    ass_path=video_ass_path,
                    output_path=output_video_path,
                )
            else:
                duration_seconds = probe_media_duration(job.tools.ffmpeg_path, job.audio_path)
                command = build_soft_subtitle_mkv_command(
                    ffmpeg_path=job.tools.ffmpeg_path,
                    image_path=job.image_path,
                    audio_path=job.audio_path,
                    ass_path=video_ass_path,
                    output_path=output_video_path,
                    video=job.video,
                    duration_seconds=duration_seconds,
                )
        elif subtitle_mode == "mp4HardSubtitles":
            if not ffmpeg_supports_filter(job.tools.ffmpeg_path, "subtitles"):
                raise RuntimeError("当前 FFmpeg 不支持 subtitles filter，无法生成 MP4 硬字幕。请安装 ffmpeg-full 或改选 MKV + ASS 软字幕。")
            output_video_path = job.output_directory / "output.mp4"
            if job.input_kind == "video":
                if job.source_video_path is None:
                    raise RuntimeError("视频任务缺少源视频路径。")
                command = build_hard_subtitle_source_video_mp4_command(
                    ffmpeg_path=job.tools.ffmpeg_path,
                    video_path=job.source_video_path,
                    ass_path=video_ass_path,
                    output_path=output_video_path,
                )
            else:
                command = build_hard_subtitle_mp4_command(
                    ffmpeg_path=job.tools.ffmpeg_path,
                    image_path=job.image_path,
                    audio_path=job.audio_path,
                    ass_path=video_ass_path,
                    output_path=output_video_path,
                    video=job.video,
                )
        else:
            raise RuntimeError(f"Unsupported subtitle output mode: {subtitle_mode}")
        try:
            run_ffmpeg(command)
            if emit:
                emit("artifact_created", stage="video", message="视频已生成", progress=1.0, path=str(output_video_path))
        finally:
            if temp_dir is not None:
                temp_dir.cleanup()

    return PipelineArtifacts(
        transcript_path=transcript_path,
        translation_path=translation_path,
        srt_path=srt_path,
        ass_path=ass_path,
        subtitle_paths=tuple(subtitle_paths),
        output_video_path=output_video_path,
    )
