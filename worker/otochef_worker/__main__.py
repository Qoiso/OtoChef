from __future__ import annotations

import argparse
import json
import sys

from .events import event_json
from .models import Job
from .pipeline import run_pipeline


def main() -> int:
    parser = argparse.ArgumentParser(prog="otochef-worker")
    parser.add_argument("--job", required=True, help="Path to job.json")
    args = parser.parse_args()

    try:
        print(event_json("job_started", message="Job started"), flush=True)
        with open(args.job, "r", encoding="utf-8") as handle:
            job = Job.from_dict(json.load(handle))
        print(event_json("stage_started", stage="pipeline", message="Processing media"), flush=True)
        artifacts = run_pipeline(job)
        print(event_json("artifact_created", stage="video", path=str(artifacts.output_video_path)), flush=True)
        print(event_json("job_finished", message="Job finished"), flush=True)
        return 0
    except Exception as error:
        print(event_json("stage_failed", stage="pipeline", message=str(error)), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
