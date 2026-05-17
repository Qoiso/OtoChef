from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path

from .asr import ASRProvider, FasterWhisperASRProvider
from .ffmpeg import build_ffmpeg_command, run_ffmpeg
from .models import Job
from .subtitles import SubtitleSegment, render_ass, render_srt
from .translation import OpenAICompatibleTranslationProvider, TranslationProvider


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
) -> PipelineArtifacts:
    job.output_directory.mkdir(parents=True, exist_ok=True)
    asr_provider = asr or FasterWhisperASRProvider(job.asr)
    translation_provider = translator or OpenAICompatibleTranslationProvider(
        job.translation,
        api_key=os.environ.get("OTOCHEF_TRANSLATION_API_KEY"),
    )

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

    srt_path = job.output_directory / "subtitles.zh.srt"
    ass_path = job.output_directory / "subtitles.zh.ass"
    srt_path.write_text(render_srt(subtitle_segments), encoding="utf-8")
    ass_path.write_text(render_ass(subtitle_segments, width=job.video.width, height=job.video.height), encoding="utf-8")

    output_video_path = job.output_directory / "output.mp4"
    if run_video:
        command = build_ffmpeg_command(
            ffmpeg_path=job.tools.ffmpeg_path,
            image_path=job.image_path,
            audio_path=job.audio_path,
            ass_path=ass_path,
            output_path=output_video_path,
            video=job.video,
        )
        run_ffmpeg(command)

    return PipelineArtifacts(
        transcript_path=transcript_path,
        translation_path=translation_path,
        srt_path=srt_path,
        ass_path=ass_path,
        output_video_path=output_video_path,
    )

