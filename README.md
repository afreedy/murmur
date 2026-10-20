# Murmur

A macOS dictation app. Hold Fn to record, or use Fn + Space for hands-free recording. Whisper transcribes locally. Optional Luna formatting sends transcript text through your signed-in Codex runtime, then pastes once into the original text field.

## Build

Apple Silicon, macOS 14+, Xcode with Icon Composer asset support, Python 3.14 and a local Whisper model are required.

```sh
python3.14 -m venv "$HOME/Library/Application Support/Murmur/runtime"
"$HOME/Library/Application Support/Murmur/runtime/bin/python" -m pip install -r requirements-local.txt
# Download the Whisper large-v3-turbo model using the upstream Whisper tooling first.
zsh build.sh
```

The model is expected at `~/.cache/whisper/large-v3-turbo.pt`. Luna uses the installed Codex app/CLI and its account limits. The app is built in `build/Murmur.app` with local ad-hoc signing. It is not notarized or distributed as an installer. Build does not replace an installed app. Microphone and Accessibility permission are needed for recording and paste.

## Behavior

- Local 16 kHz audio capture and resident Whisper transcription worker.
- Optional transcript-only online formatting with tools disabled.
- Local transcript history, scratchpad and vocabulary hints.
- Paste target guards, secure-field exclusion and clipboard restoration.
- One paste attempt; changing the destination keeps the text available to copy.

Audio stays in memory. With Luna enabled, transcript text goes to OpenAI. History and notes are stored in `~/Library/Application Support/Murmur/`; no audio, transcripts, credentials or model weights are included here.

Build success does not prove physical Fn behavior or compatibility with every editor. Some editors hide their Accessibility caret or reject paste. Existing checks and benchmarks use synthetic fixtures and require the Whisper runtime; they do not establish real-microphone accuracy.

## Source

SwiftUI/AppKit interface and recording coordination in the Swift files; Python workers in `worker.py`, `luna.py` and `jobs.py`. `Assets/Murmur.icon` is the editable Icon Composer source. Local scripts are included for icon creation and explicitly invoked synthetic checks.
