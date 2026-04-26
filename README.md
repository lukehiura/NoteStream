# NoteStream for macOS

NoteStream records audio from your Mac, turns it into a transcript, and can optionally generate notes, titles, topic timelines, and action items with AI.

It is designed for lectures, meetings, podcasts, videos, interviews, and long recordings where you want a searchable transcript and a readable summary.

## What NoteStream can do

- Record system audio from your Mac.
- Import an audio file and transcribe it.
- Show a rolling transcript while recording.
- Run a final cleanup pass after recording stops.
- Save each recording as a session.
- Export transcripts as Markdown.
- Generate AI notes, summaries, titles, action items, open questions, and topic timelines.
- Use local AI through Ollama or cloud providers such as OpenAI, Anthropic Claude, and OpenAI-compatible services.
- Optionally label speakers with an external speaker diarization tool.

## Requirements

- macOS 14 Sonoma or newer.
- Apple Silicon Mac recommended.
- Screen Recording permission enabled for NoteStream.
- Internet is optional unless you use cloud AI providers or download models.
- Local AI notes require Ollama.
- Real speaker labels require an external diarization tool and a Hugging Face token.

## Current release status

NoteStream is currently distributed as a **developer preview**: an **unsigned, ad-hoc–signed** app inside a **zip** on [GitHub Releases](https://github.com/lukehiura/NoteStream/releases). It is **not** a notarized or Developer ID–signed build, so it is not a “download and double-click for everyone” product yet.

### Developer preview (download from GitHub Releases)

1. Download the latest `NoteStream-x.y.z-developer-preview.zip`.
2. Unzip it; read `README-DEVELOPER-PREVIEW.txt` inside the zip.
3. Move `NoteStream.app` to your Applications folder (optional).
4. Open the app. If macOS blocks it, go to **System Settings → Privacy & Security** and use **Open Anyway** (or allow as prompted).
5. Grant **Screen Recording** when macOS asks (required for system audio).

Do not use developer preview builds if you are uncomfortable running unsigned software, even from a zip you trust. For the **safest** path, [build from source](#build-from-source) on your own machine.

### Build from source

From the repository root:

```bash
brew install swift-format swiftlint markdownlint-cli
swift run NoteStreamApp
```

Or use the repo [Makefile](Makefile) (`make check`, `make run`). Development setup details are in `docs/development.md`.

A signed, notarized macOS installer is **not** available yet; that would require an Apple Developer Program membership.

## First-time setup

When you open NoteStream for the first time, follow the setup checklist:

1. Grant Screen Recording permission.
2. Choose a transcription model.
3. Test audio capture.
4. Optionally enable AI notes.
5. Optionally configure speaker labels.
6. Run a short test recording.

Screen Recording permission is required because NoteStream captures audio playing on your Mac.

## Basic use

### Record system audio

1. Open NoteStream.
2. Play the lecture, meeting, podcast, or video you want to capture.
3. Click **Record system audio**.
4. Wait for the rolling transcript to appear.
5. Click **Stop & Transcribe** when finished.
6. NoteStream runs a final transcript pass and saves the session.

### Import an audio file

1. Click **Import audio file**.
2. Choose a `.wav`, `.mp3`, `.m4a`, `.caf`, or `.flac` file.
3. Wait for transcription to finish.
4. Review, copy, or export the transcript.

### Find old recordings

Use the Library sidebar to search previous sessions.

You can filter by:

- all sessions
- completed sessions
- partial sessions
- failed sessions

## Transcription models

NoteStream uses local Whisper models through WhisperKit.

The app shows simple names:

| Name in app | Internal model | Best for |
|---|---|---|
| Fast | `base.en` | Quick drafts |
| Balanced | `small.en` | Better quality |
| Accurate | `medium.en` | Best local quality |

Start with **Accurate** if your Mac can handle it. Use **Fast** if you want quicker results.

## AI notes

AI notes are optional.

When enabled, NoteStream can generate:

- a short title
- summary
- key points
- action items
- open questions
- decisions
- topic timeline
- speaker highlights

AI notes can run after recording finishes, or they can update periodically while recording.

### Recommended setup: Local Ollama

Local Ollama runs AI models on your Mac. It does not require an API key.

Use this if you want the most private setup.

#### Install Ollama

1. Download Ollama for macOS from:

```text
https://ollama.com/download/mac
```

2. Open the downloaded file.
3. Drag Ollama into Applications.
4. Open Ollama once.

#### Download a model

Open Terminal and run:

```bash
ollama pull gemma3:4b
```

This downloads a local AI model. It may take a few minutes.

#### Test Ollama

Run:

```bash
ollama run gemma3:4b
```

Type:

```text
Summarize this in one sentence: Austin built more housing and rents dropped despite population growth.
```

Exit with:

```text
/bye
```

#### Connect Ollama to NoteStream

In NoteStream:

```text
Settings → AI Notes
Provider: Local Ollama
Base URL: http://localhost:11434
Model: gemma3:4b
```

Then click **Test Ollama**.

### Other AI providers

NoteStream also supports:

| Provider | API key needed | Notes |
|---|---:|---|
| Local Ollama | No | Runs on your Mac |
| OpenAI | Yes | Good structured notes |
| Anthropic Claude | Yes | Strong summaries |
| OpenAI-compatible | Usually | Works with LM Studio, OpenRouter, LocalAI, vLLM, and similar tools |
| External executable | Depends | For advanced custom scripts |

API keys are stored in macOS Keychain.

Do not paste API keys into source code, screenshots, public issues, or README files.

## Customizing AI notes

Open:

```text
Settings → AI Notes
```

You can choose:

- note preset
- detail level
- tone
- language
- sections to include
- custom instructions
- live notes interval
- minimum new transcript text before live notes update

Recommended starting settings:

```text
Preset: Balanced
Detail: Balanced
Tone: Clean
Language: Same as transcript
Live notes: Off
Final notes after recording: On
```

For meetings, use the **Meeting** preset.

For lectures, use the **Lecture** or **Study** preset.

## Rolling live notes

Rolling live notes update while recording is still running.

They are useful for long recordings, but they are provisional. After you stop recording, NoteStream generates final notes from the final transcript.

Recommended settings:

```text
Live notes interval: 3 to 5 minutes
Minimum new text: 500 characters
Live detail: Brief
```

Shorter intervals cost more if you use a paid cloud provider and may produce noisier notes.

## Speaker labels

NoteStream can show labels such as:

```text
Speaker 1
Speaker 2
Speaker 3
```

There are two modes:

| Mode | What it means |
|---|---|
| Debug speaker labels | Fake labels for testing the interface |
| Real speaker diarization | Uses a local tool to detect who spoke when |

Debug labels do not identify real voices.

For real speaker labels, you need:

1. a Hugging Face account
2. a Hugging Face token
3. accepted pyannote model terms
4. a local diarization executable

### Hugging Face token setup

1. Create or sign in to a Hugging Face account.
2. Open:

```text
https://huggingface.co/settings/tokens
```

3. Create a read token.
4. In NoteStream, open:

```text
Settings → Speakers
```

5. Paste the token.
6. Click **Save Token**.

The token is stored in macOS Keychain.

### Real diarization backend

Advanced users can connect a local executable.

NoteStream runs it like this:

```text
/path/to/notestream-diarize --audio /path/to/audio.caf --speakers 2
```

The executable must print JSON to stdout:

```json
[
  {
    "startTime": 0.0,
    "endTime": 4.2,
    "speakerID": "speaker_1",
    "confidence": null
  }
]
```

Errors and logs must go to stderr.

A common backend is a Python script using `pyannote.audio`.

## Privacy

NoteStream saves sessions locally by default.

Local files are stored here:

```text
~/Documents/NoteStream/
```

Session folders may include:

```text
audio.caf
session.json
transcript.md
notes.md
diagnostics.jsonl
```

Important privacy notes:

- Local transcription runs on your Mac.
- Local Ollama keeps AI note generation on your Mac.
- OpenAI, Anthropic, and remote OpenAI-compatible providers send transcript text to the selected provider.
- API keys are stored in macOS Keychain.
- Diagnostics should not include raw audio, transcript text, notes text, or API keys.
- For sensitive recordings, use Local Ollama or keep AI notes disabled.
- Turn on **Delete audio after transcription** if you do not want to keep the audio file.

## Troubleshooting

### No transcript appears

Check:

1. Screen Recording permission is enabled.
2. You restarted NoteStream after granting permission.
3. Audio is actually playing on your Mac.
4. The selected transcription model has downloaded.
5. Diagnostics does not show an audio capture error.

### Recording gets stuck at startup

Try:

1. Stop the current recording.
2. Quit and reopen NoteStream.
3. Check Screen Recording permission.
4. Restart your Mac if ScreenCaptureKit is stuck.
5. Open Diagnostics and check for capture startup errors.

### AI notes do not generate

Check:

1. AI notes are enabled.
2. The selected provider is configured.
3. For Ollama, make sure Ollama is running.
4. For Ollama, make sure the model was pulled.
5. For cloud providers, make sure the API key is saved.
6. Click **Test Summarizer** in Settings.

### Ollama is not working

Run:

```bash
curl http://localhost:11434/api/tags
```

If this fails, open the Ollama app again.

If no models appear, run:

```bash
ollama pull gemma3:4b
```

### Speaker labels show too many speakers

Check the expected speaker count in:

```text
Settings → Speakers
```

If the app says debug speaker mode is active, the labels are fake test labels. Configure a real diarization backend for real speaker detection.

## Support

If NoteStream is useful, you can support development:

[![Buy Me a Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/lhiura)

Support is optional. NoteStream remains usable without donating.

## For developers

This section is only needed if you want to build or modify NoteStream from source.

### Project structure

```text
Sources/
  NoteStreamApp/              macOS app UI
  NoteStreamCore/             core models, transcript logic, notes schemas
  NoteStreamInfrastructure/   audio capture, persistence, WhisperKit, HTTP adapters
Tests/
  NoteStreamCoreTests/
  NoteStreamInfrastructureTests/
docs/
  architecture.md
  manual-smoke-test.md
```

### Build from source

Install Xcode, then run:

```bash
swift build
make test
```

(`make test` runs `swift test` with flags that match CI; prefer it over a bare `swift test` on Swift 6 toolchains.)

### Continuous integration

The CI pipeline checks:

- Swift build
- Swift tests
- code coverage
- Swift formatting
- SwiftLint
- Markdown linting
- obvious API key leaks
- committed recording/session artifacts

### Storage layout

```text
~/Documents/NoteStream/
  Sessions/
    <session-uuid>/
      audio.caf
      session.json
      transcript.md
      notes.md
      diagnostics.jsonl
  Diagnostics/
    app.jsonl
```

### Architecture

```text
SwiftUI macOS app
→ ScreenCaptureKit audio capture
→ AVFoundation conversion
→ WhisperKit local transcription
→ TranscriptCoordinator
→ session storage
→ optional AI notes
→ optional speaker diarization
```

### Transcript stability rule

During rolling transcription:

- committed transcript segments are append-only
- draft tail is the only region allowed to change
- final transcription can replace the rolling result after recording stops

## Release notes

See `CHANGELOG.md` for release history.
