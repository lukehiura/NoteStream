# NoteStream (macOS)

SwiftUI-first macOS lecture notes app.

V1 is intentionally **rolling transcription** (updates every few seconds) plus a **final cleanup pass** after stopping.

## Support

If NoteStream is useful, you can support development:

[![Buy Me a Coffee](https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png)](https://www.buymeacoffee.com/lhiura)

Support is optional. NoteStream remains usable without donating.

## Architecture (v1)

```text
SwiftUI UI (macOS app)
→ ScreenCaptureKit system audio capture (record + optional rolling chunks)
→ AVFoundation conversion (48k stereo → 16k mono)
→ WhisperKit local transcription
→ TranscriptCoordinator (committed transcript + draft tail)
→ JSON session folder + Markdown export
→ optional AI notes generation
   → Local Ollama
   → OpenAI
   → Anthropic Claude
   → OpenAI-compatible endpoint
   → external executable
```

### Transcript stability rule

**Everything above the draft tail is immutable.**

- **Committed** segments: append-only, never edited in place.
- **Draft tail**: only region allowed to change while recording.

## Storage layout (v1)

```text
~/Documents/NoteStream/
  Sessions/
    <session-uuid>/
      audio.caf                 # optional, deleted if "delete audio after transcription" is enabled
      session.json              # transcript segments, metadata, notes field
      transcript.md             # exported readable transcript
      notes.md                  # generated AI notes, when available
      diagnostics.jsonl         # per-session diagnostics
  Diagnostics/
    app.jsonl
```

## Repo layout

- `Package.swift`: Swift Package manifest
- `Sources/NoteStreamCore/`: core domain + coordinator (UI-agnostic)
- `.cursor/rules/`: Cursor rules for this repo (Swift/macOS-first)

## Getting started (dev)

This repo ships a Swift Package (`NoteStreamCore`). For the macOS app UI:

1. Create a **new Xcode macOS App** project (SwiftUI lifecycle) in this repo (e.g. `NoteStreamApp/`).
2. Add `NoteStreamCore` as a local Swift Package dependency.
3. Implement phases:
   - Phase 1: drag-and-drop audio file → transcribe → show transcript
   - Phase 2: ScreenCaptureKit record system audio → transcribe after stop
   - Phase 3: rolling chunks (every ~8s) → provisional transcript tail
   - Phase 4: final full-file pass replaces rolling transcript

## Real speaker diarization (external tool)

NoteStream can label **who spoke when** by running a **local executable** you provide. The app invokes:

```text
/path/to/notestream-diarize --audio /path/to/audio.caf --speakers 2
```

The process must print **only** JSON to **stdout** (errors and logs go to **stderr**). Each element matches the `SpeakerTurn` shape, for example:

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

NoteStream aligns those time ranges to transcript segments. **Debug builds** may use a built-in **fake** diarizer for UI testing; it does **not** detect real voices. For real diarization, configure a Hugging Face token and a diarization executable under **Settings → Speakers**.

## Real speaker diarization credentials

Real speaker diarization uses a local executable backend. The recommended backend uses pyannote models from Hugging Face.

To enable it:

1. Create or sign in to a Hugging Face account.
2. Accept the required pyannote model conditions:
   - `pyannote/segmentation-3.0`
   - `pyannote/speaker-diarization-3.1`
3. Create a Hugging Face access token with read access.
4. Open NoteStream:
   - Settings → Speakers
   - Paste the Hugging Face token
   - Click Save Token
   - Choose the diarization executable
   - Click Test Real Diarizer

The token is stored in macOS Keychain. It is not stored in `UserDefaults` and should never be committed to git.

When NoteStream launches your executable, it injects the same token into the subprocess environment (so your script does not rely on a globally exported shell variable). Keep stdout strictly JSON; write diagnostics to stderr.

### Example: Python + pyannote

A common approach is a small Python script using [pyannote.audio](https://github.com/pyannote/pyannote-audio) (PyTorch) with a pipeline such as [`pyannote/speaker-diarization-3.1`](https://huggingface.co/pyannote/speaker-diarization-3.1). You typically need:

1. A Python 3 venv with `pyannote.audio` (3.1+), `torch`, and `torchaudio` installed.
2. A [Hugging Face](https://huggingface.co) account, access token, and acceptance of the model terms for the pipeline you use.
3. `ffmpeg` on your `PATH` (e.g. `brew install ffmpeg`) if you convert CAF/WAV to the mono 16 kHz input your script expects.

In your script, read the token from the environment (NoteStream sets it when it runs the tool):

```python
import os

hf_token = (
    os.environ.get("HF_TOKEN")
    or os.environ.get("HUGGINGFACE_TOKEN")
    or os.environ.get("HUGGING_FACE_HUB_TOKEN")
)

if not hf_token:
    raise SystemExit("Hugging Face token is missing. Add it in NoteStream Settings → Speakers.")
```

For pyannote 3.1 you can load the pipeline with either `token=` or `use_auth_token=` depending on library version. Keep stdout strictly JSON; write diagnostics to stderr.

## AI notes setup

NoteStream can generate AI notes and titles from the final transcript.

The **default local provider** we recommend is **Local Ollama**: it runs on your Mac, does not require a cloud API key or paid provider account (it still uses local CPU/GPU resources and you must download a model). You can also use OpenAI, Anthropic Claude, an OpenAI-compatible endpoint, or an advanced external executable.

Structured JSON outputs from Ollama and OpenAI fit the `NotesSummary` schema used by the app; see the [Ollama structured outputs documentation][1].

Settings includes **native providers** (Ollama, OpenAI, Anthropic, OpenAI-compatible HTTP) plus **External executable** for custom scripts. API keys for cloud providers are stored in the **macOS Keychain**; model name, base URL, and presets live in app preferences. For long recordings with **Local Ollama**, NoteStream uses a **chunked summarize → merge** pipeline when the committed transcript exceeds about ten minutes, so smaller models stay responsive.

### Supported providers

| Provider | Requires API key | Requires internet | Recommended use |
|---|---:|---:|---|
| Local Ollama | No | No, after model download | Default local provider |
| OpenAI | Yes | Yes | Best structured JSON reliability |
| Anthropic Claude | Yes | Yes | Strong summarization quality |
| OpenAI-compatible | Usually | Depends | OpenRouter, LM Studio, LocalAI, vLLM, etc. |
| External executable | No, unless your script uses one | Depends | Advanced custom integrations |

API keys should never be committed to the repo. If the native provider settings are enabled, NoteStream stores API keys in macOS Keychain. Provider name, model name, base URL, and non-secret settings are stored in app preferences.

### Recommended default: Local Ollama

Ollama runs a local HTTP API on your Mac so NoteStream can call a model without a cloud API key (you still download model weights and use CPU/GPU RAM).

#### 1. Install Ollama on macOS

**Official app (recommended):** download the macOS installer from [Ollama’s macOS download page](https://ollama.com/download/mac). Open the `.dmg` and drag **Ollama** into **Applications**. Ollama expects **macOS 14 Sonoma** or later. After installing, launch **Ollama** from **Applications** once so the app and background service can start.

**Shell install (optional):** if you prefer the documented one-liner, review the script before you run it, then:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

#### 2. Pull the model NoteStream should use

**gemma3:4b** is a good first choice on many recent Macs: Gemma 3 is listed on Ollama in **1B**, **4B**, **12B**, and **27B** sizes, and the **4B** variant is roughly **3.3 GB** on disk.

```bash
ollama pull gemma3:4b
```

In the app you can instead use **Settings → LLM Notes → Local model preset** (**Auto** picks a tag from your Mac’s unified memory) or **Recommended** next to **Refresh models** to apply the memory-based default tag.

### Local model discovery

When **Provider** is set to **Local Ollama**, NoteStream can detect locally installed models by calling:

```text
GET http://localhost:11434/api/tags
```

Open **Settings → LLM Notes** (with Local Ollama selected) to refresh the list automatically, or use **Refresh models** to update the installed model list.

If no models are found, install one with:

```bash
ollama pull gemma3:4b
```

or click **Pull recommended** in Settings.

You can still type a **custom model name** (choose **Custom…** or use the manual field when no models are detected) if you use a model that does not appear in the detected list.

#### 3. Test that it works

```bash
ollama run gemma3:4b
```

At the prompt, try:

```text
Summarize this in one sentence: Austin built more housing and rents dropped despite population growth.
```

Exit the REPL with:

```text
/bye
```

#### 4. Confirm the local server is running

```bash
curl http://localhost:11434/api/tags
```

You should see JSON listing installed models (for example `gemma3:4b`).

#### 5. Configure NoteStream

```text
Settings
→ LLM Notes
→ Provider: Local Ollama
→ Local model preset: Auto (or Small / Balanced / High Quality / Custom)
→ Base URL: http://localhost:11434
→ Generate notes after recording: On
→ Test Ollama
```

If you use **Custom** as the preset, set **Ollama model tag** to `gemma3:4b` (or whatever you pulled). The **Hardware tiers** disclosure in Settings summarizes suggested tags by unified memory (for example **gemma3:4b** on many 16 GB Apple Silicon Macs, stepping up to **qwen3.5:9b** / **gemma3:12b** / **gemma3:27b** on larger pools).

#### Optional: stronger quality on bigger Macs

```bash
ollama pull qwen3.5:9b
```

Then in **Settings → LLM Notes**, choose a preset that maps to that tag, or **Custom** with model tag `qwen3.5:9b`.

Start with **gemma3:4b**; it is the safest default for most recent Macs before you move to larger models.

### OpenAI setup

Use OpenAI if you want high reliability for structured JSON notes.

1. Create or sign in to an OpenAI developer account.
2. Create an API key in the OpenAI dashboard.
3. In NoteStream:

```text
Settings
→ LLM Notes
→ Provider: OpenAI
→ Model name: gpt-4o-mini
→ Paste API key
→ Save API Key
→ Generate notes after recording: On
→ Test summarizer
```

Recommended starting model:

```text
gpt-4o-mini
```

Use a stronger model if summaries need better reasoning or longer context.

Do not paste your OpenAI API key into source code, shell scripts committed to git, screenshots, or README files.

### Anthropic Claude setup

Use Anthropic if you prefer Claude for summarization.

1. Create or sign in to an Anthropic Console account.
2. Create an API key.
3. In NoteStream:

```text
Settings
→ LLM Notes
→ Provider: Anthropic Claude
→ Model name: claude-3-5-haiku-latest
→ Paste API key
→ Save API Key
→ Generate notes after recording: On
→ Test summarizer
```

Alternative model choices depend on what your Anthropic account has access to.

Do not commit your Anthropic API key to the repo.

### OpenAI-compatible setup

Use this for providers or local servers that expose an OpenAI-compatible API.

Examples:

```text
LM Studio
OpenRouter
LocalAI
vLLM
llama.cpp server wrappers
company-hosted OpenAI-compatible gateways
```

In NoteStream:

```text
Settings
→ LLM Notes
→ Provider: OpenAI Compatible
→ Base URL: http://localhost:1234
→ Model name: your-model-name
→ API key: optional or provider-specific
→ Save API Key, if needed
→ Generate notes after recording: On
→ Test summarizer
```

For LM Studio, start the local server from the Developer or Server tab, then use its local base URL. Many local OpenAI-compatible servers use a `/v1` path, such as:

```text
http://localhost:1234/v1
```

If the test fails, check:

```text
Base URL
Model name
Whether the local server is running
Whether the provider supports the endpoint NoteStream is calling
Whether an API key is required
```

### External executable setup

The external executable provider is for advanced users who want to own the entire LLM integration.

NoteStream sends JSON to the executable through stdin and expects JSON back through stdout.

Request shape:

```json
{
  "transcriptMarkdown": "[00:00] Speaker 1: Example transcript text.",
  "previousNotesMarkdown": null,
  "mode": "final",
  "preferences": {
    "detailLevel": "balanced",
    "tone": "clean",
    "language": "sameAsTranscript",
    "sections": {
      "summary": true,
      "keyPoints": true,
      "actionItems": true,
      "openQuestions": true,
      "decisions": false,
      "topicTimeline": true,
      "speakerHighlights": false
    },
    "customInstructions": "",
    "liveUpdateStyle": "brief"
  }
}
```

The `preferences` object reflects **Settings → AI Notes → Note Format** (detail, tone, language, which sections to emphasize, custom instructions, and live-update brevity). Older scripts that only read `transcriptMarkdown`, `previousNotesMarkdown`, and `mode` can ignore `preferences`; parsers that accept unknown keys can drop it.

Response shape:

```json
{
  "title": "Short Recording Title",
  "summaryMarkdown": "## Summary\n...\n\n## Key Points\n- ...\n\n## Action Items\n- ...\n\n## Open Questions\n- ...",
  "keyPoints": ["..."],
  "actionItems": [],
  "openQuestions": []
}
```

Example executable path:

```text
~/NoteStreamTools/notestream-summarize.py
```

Make it executable:

```bash
chmod +x ~/NoteStreamTools/notestream-summarize.py
```

Then configure NoteStream:

```text
Settings
→ LLM Notes
→ Provider: External Executable
→ Notes summarizer executable path: ~/NoteStreamTools/notestream-summarize.py
→ Test summarizer
```

### How AI notes work

After recording stops, NoteStream runs this pipeline:

```text
final transcript
→ optional speaker diarization
→ transcript markdown
→ selected LLM provider
→ structured NotesSummary JSON
→ generated title + notes markdown
→ session save
```

For live notes, NoteStream waits until enough committed transcript text exists, then sends only the new committed transcript plus the previous notes to the selected provider.

Recommended defaults:

```text
Provider: Local Ollama
Model: llama3.2
Generate notes after recording: Off by default
Live notes: Off by default
Live interval: 5 minutes
```

Users should explicitly enable AI notes because transcript text may be sent to an external provider depending on the selected provider.

### Troubleshooting AI notes

If notes are not generated:

1. Open Settings.
2. Check the selected provider.
3. Click Test summarizer.
4. Confirm the model name is valid.
5. Confirm the base URL is correct.
6. Confirm the API key is saved if the provider requires one.
7. Check the Notes status message in the app.
8. Check diagnostics logs if the app reports a provider error.

Common issues:

```text
Local Ollama
- Ollama is not running.
- The model has not been pulled.
- Base URL is wrong.

OpenAI
- API key is missing or invalid.
- Model name is wrong.
- Billing or usage limits are not configured.

Anthropic
- API key is missing or invalid.
- Model name is not available to your account.
- Account access or billing is not configured.

OpenAI-compatible
- Base URL is missing /v1 or has an extra /v1.
- The local server is not running.
- The provider does not support structured output.
- Model name does not match the server’s loaded model.

External executable
- File is not executable.
- Script writes logs to stdout instead of stderr.
- Script returns invalid JSON.
- Script exits with non-zero status.
```

### Privacy notes

Local Ollama keeps transcript text on your Mac after the model is downloaded.

OpenAI, Anthropic, and remote OpenAI-compatible providers send transcript text to the selected provider.

External executable behavior depends on what the executable does.

For sensitive recordings, use Local Ollama or keep AI notes disabled.

### Support and donations

The app’s **Settings → General → Support** section contains placeholder links. Replace the URLs in `Sources/NoteStreamApp/Views/Settings/GeneralSettingsView.swift` (`AppSupportLinks`) with your public repository and your preferred sponsorship or donation page (for example [GitHub Sponsors](https://github.com/sponsors) or another provider).

[1]: https://docs.ollama.com/capabilities/structured-outputs
