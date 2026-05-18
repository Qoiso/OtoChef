from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
from typing import Callable

from .asr import ASRProvider, FasterWhisperASRProvider
from .ffmpeg import build_ffmpeg_command, ffmpeg_supports_filter, probe_media_duration, run_ffmpeg
from .models import Job
from .subtitles import SubtitleSegment, render_ass, render_srt
from .translation import OpenAICompatibleTranslationProvider, TranslationProvider


PipelineEventEmitter = Callable[..., None]


@dataclass(frozen=True)
class PipelineArtifacts:
    transcript_path: Path
    translation_path: Path
    srt_path: Path
    ass_path: Path
    output_video_path: Path


def _write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def run_pipeline(
    job: Job,
    asr: ASRProvider | None = None,
    translator: TranslationProvider | None = None,
    run_video: bool = True,
    emit: PipelineEventEmitter | None = None,
) -> PipelineArtifacts:
    job.output_directory.mkdir(parents=True, exist_ok=True)
    asr_provider = asr or FasterWhisperASRProvider(
        job.asr,
        search_roots=[
            job.output_directory.parent,
            job.output_directory.parent.parent,
        ],
    )
    translation_provider = translator or OpenAICompatibleTranslationProvider(
        job.translation,
        api_key=os.environ.get("OTOCHEF_TRANSLATION_API_KEY"),
    )

    if emit:
        emit("stage_started", stage="asr", message="正在加载 ASR 模型并识别日语音频", progress=0.05)
    transcript_segments = asr_provider.transcribe(job.audio_path)
    transcript_path = job.output_directory / "transcript.ja.json"
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

    if emit:
        emit("stage_started", stage="translation", message="正在翻译中文字幕", progress=0.45)
    translated_text = translation_provider.translate(transcript_segments)
    subtitle_segments = [
        SubtitleSegment(
            segment_id=segment.segment_id,
            start=segment.start,
            end=segment.end,
            text=translated_text[segment.segment_id],
        )
        for segment in transcript_segments
    ]
    translation_path = job.output_directory / "translation.zh.json"
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
                for segment in subtitle_segments
            ]
        },
    )
    if emit:
        emit("artifact_created", stage="translation", message="中文字幕翻译已完成", progress=0.65, path=str(translation_path))

    if emit:
        emit("stage_started", stage="subtitle", message="正在生成字幕文件", progress=0.70)
    srt_path = job.output_directory / "subtitles.zh.srt"
    ass_path = job.output_directory / "subtitles.zh.ass"
    srt_path.write_text(render_srt(subtitle_segments), encoding="utf-8")
    ass_path.write_text(render_ass(subtitle_segments, width=job.video.width, height=job.video.height), encoding="utf-8")
    if emit:
        emit("artifact_created", stage="subtitle", message="SRT 字幕已生成", progress=0.78, path=str(srt_path))
        emit("artifact_created", stage="subtitle", message="ASS 字幕已生成", progress=0.82, path=str(ass_path))

    output_video_path = job.output_directory / "output.mp4"
    if run_video:
        if emit:
            emit("stage_started", stage="ffmpeg", message="正在调用 FFmpeg 合成视频", progress=0.86)
        burn_subtitles = ffmpeg_supports_filter(job.tools.ffmpeg_path, "subtitles")
        duration_seconds = None
        if not burn_subtitles:
            duration_seconds = probe_media_duration(job.tools.ffmpeg_path, job.audio_path)
            if emit:
                emit("warning", stage="ffmpeg", message="当前 FFmpeg 不支持 subtitles filter，已改用 MP4 软字幕轨。")
        command = build_ffmpeg_command(
            ffmpeg_path=job.tools.ffmpeg_path,
            image_path=job.image_path,
            audio_path=job.audio_path,
            ass_path=ass_path,
            srt_path=srt_path,
            output_path=output_video_path,
            video=job.video,
            burn_subtitles=burn_subtitles,
            duration_seconds=duration_seconds,
        )
        run_ffmpeg(command)
        if emit:
            emit("artifact_created", stage="video", message="视频已生成", progress=1.0, path=str(output_video_path))

    return PipelineArtifacts(
        transcript_path=transcript_path,
        translation_path=translation_path,
        srt_path=srt_path,
        ass_path=ass_path,
        output_video_path=output_video_path,
    )
