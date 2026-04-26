#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import torch
from pyannote.audio import Pipeline


def fail(message: str, code: int = 1) -> None:
    print(message, file=sys.stderr)
    sys.exit(code)


def token_from_environment() -> str:
    token = (
        os.environ.get("HF_TOKEN")
        or os.environ.get("HUGGINGFACE_TOKEN")
        or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    )

    if not token:
        fail("Hugging Face token is missing. Add it in NoteStream Settings → Speakers.")

    return token


def convert_to_wav_16k_mono(input_path: Path) -> Path:
    output = Path(tempfile.gettempdir()) / f"notestream-diarize-{os.getpid()}.wav"

    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(input_path),
        "-ac",
        "1",
        "-ar",
        "16000",
        "-vn",
        str(output),
    ]

    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    if result.returncode != 0:
        fail(f"ffmpeg failed: {result.stderr.strip()}")

    return output


def normalize_speaker_id(raw: str) -> str:
    digits = "".join(ch for ch in raw if ch.isdigit())

    if digits:
        return f"speaker_{int(digits) + 1}"

    return raw.lower().replace(" ", "_")


def load_pipeline(pipeline_id: str, token: str):
    try:
        return Pipeline.from_pretrained(pipeline_id, token=token)
    except TypeError:
        return Pipeline.from_pretrained(pipeline_id, use_auth_token=token)


def main() -> None:
    parser = argparse.ArgumentParser(description="NoteStream pyannote diarization helper")
    parser.add_argument("--audio", required=True, help="Path to audio file")
    parser.add_argument("--speakers", type=int, default=None, help="Expected speaker count")
    parser.add_argument(
        "--pipeline",
        default="pyannote/speaker-diarization-3.1",
        help="Hugging Face pyannote pipeline id",
    )
    args = parser.parse_args()

    audio_path = Path(args.audio).expanduser().resolve()

    if not audio_path.exists():
        fail(f"Audio file does not exist: {audio_path}")

    hf_token = token_from_environment()
    wav_path = convert_to_wav_16k_mono(audio_path)

    try:
        pipeline = load_pipeline(args.pipeline, hf_token)

        if torch.backends.mps.is_available():
            pipeline.to(torch.device("mps"))
        elif torch.cuda.is_available():
            pipeline.to(torch.device("cuda"))

        kwargs = {}
        if args.speakers and args.speakers > 0:
            kwargs["num_speakers"] = args.speakers

        diarization = pipeline(str(wav_path), **kwargs)

        turns = []
        for segment, _, speaker in diarization.itertracks(yield_label=True):
            start = float(segment.start)
            end = float(segment.end)

            if end <= start or (end - start) < 0.05:
                continue

            turns.append(
                {
                    "startTime": start,
                    "endTime": end,
                    "speakerID": normalize_speaker_id(str(speaker)),
                    "confidence": None,
                }
            )

        print(json.dumps(turns, ensure_ascii=False))

    except Exception as exc:
        fail(f"pyannote diarization failed: {exc}")

    finally:
        try:
            wav_path.unlink(missing_ok=True)
        except Exception:
            pass


if __name__ == "__main__":
    main()

