# Claude Code Shared Configurations

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents and skills for our team.

## Structure

```
agents/                             # Custom agent definitions
skills/                             # Custom skill definitions
hooks/                              # Claude Code hooks (install into settings.json)
claude-code-multi-agent-iterm2.md   # Host-side iTerm2/tmux setup for agent teams (non-Docker)
```

## Usage

### Agents

Copy agent files to your local Claude Code config:

```bash
cp agents/*.md ~/.claude/agents/
```

Or symlink the directory for auto-updates when you pull:

```bash
ln -sf "$(pwd)/agents"/*.md ~/.claude/agents/
```

### Skills

Copy skill directories to your local Claude Code config:

```bash
cp -r skills/* ~/.claude/skills/
```

### Hooks

Copy the hook scripts and register them in `~/.claude/settings.json`:

```bash
mkdir -p ~/.claude/hooks && cp hooks/*.sh ~/.claude/hooks/
```

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent|Workflow",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/hooks/limit-agent-spawns.sh" }
        ]
      }
    ]
  }
}
```

Running inside `claude-docker`? `~/.claude/{agents,skills,commands,CLAUDE.md}` are mounted read-only from the host and `settings.json` is seeded from the container image, so hooks registered in your host `settings.json` do not run in the container. Edit this repo and sync to the host config instead of editing the mounted copies.

### claude-docker

`claude-docker` — the hardened container for running Claude Code with isolated filesystem access and `gh`/`glab`/`aws` pre-installed — now lives in its own repository: [schubergphilis/claude-docker](https://github.com/schubergphilis/claude-docker). See its README for the quickstart.

## Available Agents

| Agent | Model | Effort | Description |
|-------|-------|--------|-------------|
| `architect` | opus | session | Infrastructure and platform architecture authority |
| `cost-control-reviewer` | sonnet | session | FinOps and cost optimization specialist |
| `mission-critical-engineer` | sonnet | session | Hands-on implementer and debugger |
| `principal-engineer` | opus | session | System design and cross-cutting architectural decisions |
| `qa-pipeline-expert` | sonnet | session | Testing, linting, and CI/CD pipeline expert |
| `security-devils-advocate` | opus | session | Adversarial security reviewer |
| `tech-lead` | fable | low | PR/MR reviewer and pragmatic generalist; cannot spawn subagents |

"session" means the agent inherits the effort level of the session that spawned it.

## Available Skills

| Skill | Description |
|-------|-------------|
| `github` | `gh` reference: PR creation, inline reviews via `gh api`, run monitoring, review policy |
| `gitlab` | `glab` reference: MR creation/update, inline MR review via `glab api`, CI status/trace/retry, VPN diagnostics |
| `create-team` | Creates an agent team with `TeamCreate`; enforces the delegation cap below |
| `spec` | Spec-Driven Development (OpenSpec format, behavioral testing, backfilling) |

## Available Hooks

| Hook | Event | Description |
|------|-------|-------------|
| `limit-agent-spawns.sh` | `PreToolUse` on `Agent` and `Workflow` | Denies the 3rd subagent spawn per session and any `Workflow` run until the user raises the cap |

## Delegation Policy

Two rules apply across the agents, skills, and hook in this repo:

1. **PR/MR reviews run on Claude Fable 5.1 at low effort.** The `tech-lead` agent pins `model: fable` and `effort: low`; the `github` and `gitlab` skills route reviews to it. `/code-review low` is the fallback when the session model is already Fable (it runs on the session model; always type the level, a bare `/code-review` reuses the last level typed). Low effort yields fewer, high-confidence findings, which is what a review should be.
2. **At most 2 spawned agents per session without explicit approval.** `Workflow` runs always need approval. The `create-team` skill and the `tech-lead` agent (which cannot spawn at all) follow this in their instructions; `limit-agent-spawns.sh` enforces it. The hook denies with a message that tells Claude to stop and ask, and prints the command that raises the cap once you have approved.

Put the same two rules in your global `~/.claude/CLAUDE.md` so the main session follows them even when no agent or skill is loaded:

```markdown
## Reviews and Delegation
- PR/MR reviews run on Claude Fable 5.1 at low effort. Delegate to the `tech-lead` agent (pinned to `model: fable`, `effort: low`). Only use `/code-review low` when the session model is already Fable, and always type the level. One reviewer, no fan-out across files or dimensions.
- Never spawn more than 2 agents (Agent calls, team teammates, Workflow runs) in a session without my explicit approval. Ask first, listing what each agent would do. Workflow runs always need approval.
- Delegating a review to `tech-lead` counts as one of the 2.
```

## Contributing

1. Create or modify agent/skill files following the [Claude Code agent format](https://docs.anthropic.com/en/docs/claude-code/agents)
2. Open a PR with your changes
3. Get a review from a colleague before merging
