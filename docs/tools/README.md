# NoteStream tools

## pyannote speaker diarization helper

This folder contains a starter Python script for real speaker diarization.

Install:

```bash
python3 -m venv ~/.notestream-diarizer
source ~/.notestream-diarizer/bin/activate
python -m pip install --upgrade pip
pip install "pyannote.audio>=3.1" torch torchaudio
brew install ffmpeg
```

Copy the helper:

```bash
mkdir -p ~/NoteStreamTools
cp docs/tools/notestream-diarize-pyannote.py ~/NoteStreamTools/notestream-diarize
chmod +x ~/NoteStreamTools/notestream-diarize
```

Then in NoteStream:

```text
Settings → Speakers → Real Diarization Backend → Choose…
```

Choose:

```text
~/NoteStreamTools/notestream-diarize
```

The helper reads the Hugging Face token from environment variables injected by NoteStream.
