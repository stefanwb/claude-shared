# Claude Code Multi-Agent Setup (iTerm2 / macOS)

> Running Claude Code inside `claude-docker`? Use its built-in `--iterm` / `--tmux` flags instead — see [`claude-docker/README.md`](claude-docker/README.md#split-pane-agent-teams). This doc covers host-side (non-Docker) setup only.

## Prerequisites

- Claude Code CLI installed
- iTerm2 on macOS

## Option A: In-Process Mode (simplest)

All agents run in your main terminal. Cycle through them with **Shift+Down**.

Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process"
}
```

No extra setup needed — works in any terminal.

## Option B: Split-Pane Mode (each agent gets its own pane)

### 1. Install the `it2` CLI

```bash
brew install mkusaka/tap/it2
```

Verify: `which it2`

### 2. Enable iTerm2 Python API

**iTerm2 → Settings → General → Magic → Enable Python API** ✓

### 3. Configure Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "tmux"
}
```

> Setting `teammateMode` to `"tmux"` auto-detects iTerm2 vs plain tmux.

### Alternative: tmux via iTerm2

For best results on macOS, the docs recommend launching tmux in iTerm2 integration mode:

```bash
tmux -CC
```

Then run `claude` inside that session.

## Usage

```bash
claude
# Ask Claude to create a team, e.g.:
# "Create a team with a researcher and an implementer"
```

Or override mode for a single session:

```bash
claude --teammate-mode in-process
```

## Troubleshooting

| Problem | Fix |
|---|---|
| Split panes not appearing | Check `which it2` is in PATH and Python API is enabled |
| Orphaned tmux sessions | `tmux kill-session -t <session-name>` |
| Want to skip panes entirely | Use `"teammateMode": "in-process"` |

## Notes

- Agent teams are **experimental** — expect rough edges around session resumption and shutdown
- VS Code integrated terminal does **not** support split panes; use in-process mode there
