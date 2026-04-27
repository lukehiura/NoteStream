# Diarization tool (Python)

This folder documents **the optional Python pyannote-based diarization helper** only. App UX for speakers lives in the macOS app; for architecture, see `../architecture.md`.

## What it does

`notestream-diarize-pyannote.py` is a **reference executable** you can copy and run as the “Real diarization backend” in **Settings → Speakers**. It reads an audio file path and speaker count, runs pyannote, and prints **JSON speaker turns to stdout** (errors to stderr). NoteStream parses stdout as JSON.

## Requirements

- **Python 3** with a venv (recommended)
- **Packages:** `pyannote.audio` (3.x), `torch`, `torchaudio` (see script header / your hardware)
- **ffmpeg** on `PATH` (e.g. `brew install ffmpeg`)
- **Hugging Face** token with access to the pyannote model cards you use (app stores token in Keychain and passes env to the process)

## Environment

NoteStream injects token-related environment when launching the tool (see app settings). Do not commit tokens; configure them only in the app or your shell for local tests.

## I/O contract

- **Args:** `--audio <path>` (required), `--speakers <n>` (optional hint), `--pipeline <hf id>` (default `pyannote/speaker-diarization-3.1`). See `notestream-diarize-pyannote.py`.
- **Token:** `HF_TOKEN`, `HUGGINGFACE_TOKEN`, or `HUGGING_FACE_HUB_TOKEN` (NoteStream sets these when launching the tool).
- **Output:** one JSON array on stdout; each turn has `startTime`, `endTime`, `speakerID`, `confidence` (may be `null`).

## Example: install and point the app

```bash
python3 -m venv ~/.notestream-diarizer
source ~/.notestream-diarizer/bin/activate
pip install "pyannote.audio>=3.1" torch torchaudio
brew install ffmpeg
cp docs/tools/notestream-diarize-pyannote.py ~/NoteStreamTools/notestream-diarize
chmod +x ~/NoteStreamTools/notestream-diarize
```

In NoteStream: **Settings → Speakers → Real diarization backend →** choose that executable.

## CI

`make python-tools-check` runs `py_compile` on this script so obvious syntax errors fail fast; it does not run inference.
