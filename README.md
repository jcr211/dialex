# Dialex

Dialex is a warm, nostalgic audio wrapper for Codex CLI.

It is designed around interactive Codex first, with a hook-ready runtime for future Codex prompt and thinking events.

It adds subtle modem-era inspired cues for:

- `codex` launch and exit
- `codex exec --json` event streaming
- `review`, `resume`, `fork`, and `apply` flows
- future prompt, thinking, tool-action, and completion hook events

## What it sounds like

The palette is intentionally soft:

- gentle startup sweeps
- rounded chimes
- soft reconnect chirps
- muted confirmation tones
- non-jarring error cues

The goal is to feel intuitive and pleasant, not noisy or arcade-like.

## Install

Windows / PowerShell:

```powershell
npm install -g git+https://github.com/jcr211/dialex.git
dialex install
```

After install:

- `codex` uses the audio wrapper
- `codex-native` bypasses the wrapper
- `CODEX_AUDIO_DISABLED=1` disables audio

## Event-driven mode

Dialex becomes more expressive when you use:

```powershell
codex exec --json "..."
```

That lets it react to the JSONL event stream emitted by Codex exec mode.

## Interactive-first design

Dialex is centered on normal interactive `codex` usage.

Today:

- interactive `codex` gets stable wrapper sounds on launch and completion
- `codex exec --json` gets richer event-driven behavior

The repo now also includes a hook-ready runtime in `dialex-hook.ps1` for future Codex interactive hooks. That runtime already supports these event names:

- `prompt-submit`
- `thinking-start`
- `thinking-stop`
- `tool-action`
- `turn-complete`
- `error`

Those hook events are not wired into interactive Codex yet because the current external wrapper path still does not expose a stable public hook surface for the TUI.

## Uninstall

```powershell
pwsh ./uninstall.ps1
```

## Notes

- This is currently Windows / PowerShell first.
- The install script copies the audio bridge into `~/.codex/dialex`.
- The audio bridge uses your local Codex CLI install; it does not replace it.
- The npm package is just the delivery mechanism. The actual profile hook still lands in your PowerShell profile and `.codex` folder.
- Public repo: `https://github.com/jcr211/dialex`
