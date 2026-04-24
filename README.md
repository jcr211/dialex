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

- interactive `codex` gets a live "windchime" of cues driven by Codex's session log
- `codex exec --json` gets richer event-driven behavior off the JSON stream
- launch / completion still get their own wrapper-played cues

### Session-tail runtime

When you launch interactive `codex`, Dialex spawns a background tailer that
follows the rollout JSONL Codex writes under `~/.codex/sessions/`. As events
land, the tailer plays cues for:

- task start and completion
- user prompts and assistant messages
- shell command starts, successes, and errors
- file patches via `apply_patch`
- MCP tool calls, web fetches, and searches
- subagent spawn / wait / close

A short per-cue cooldown keeps bursty stretches from crashing together. Set
`CODEX_AUDIO_DISABLED=1` to silence the tailer along with the wrapper.

### Hook runtime

The repo also includes `dialex-hook.ps1` for direct use from Codex's hook
surface (`hooks.json`). It supports these event names:

- `prompt-submit`
- `thinking-start`
- `thinking-stop`
- `tool-action`
- `turn-complete`
- `error`

OpenAI currently disables hooks on Windows in their docs, so the tailer is the
primary path on Windows today. The hook script is ready for the moment that
gate lifts (or for use on other platforms).

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
