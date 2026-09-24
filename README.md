# Claude Code Shared Configurations

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents and skills for our team.

## Structure

This repo is a Claude Code [plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces) with two plugins:

```
.claude-plugin/marketplace.json     # Marketplace: lists both plugins
.claude-plugin/plugin.json          # Plugin `claude-shared` (the repo root)
agents/                             # claude-shared: agent definitions
skills/                             # claude-shared: skills
hooks/                              # claude-shared: spawn-cap hook + hooks.json
plugins/guardrails/                 # Plugin `guardrails`: command and file-edit guards
claude-code-multi-agent-iterm2.md   # Host-side iTerm2/tmux setup for agent teams (non-Docker)
```

## Usage

Add the marketplace and enable the plugins in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-shared": {
      "source": { "source": "github", "repo": "stefanwb/claude-shared" }
    }
  },
  "enabledPlugins": {
    "claude-shared@claude-shared": true,
    "guardrails@claude-shared": true
  }
}
```

Claude Code installs both on the next start. To pin a release, add `"ref": "<tag>"` to the `source` object. Or install interactively:

```bash
claude plugin marketplace add stefanwb/claude-shared
claude plugin install claude-shared@claude-shared
claude plugin install guardrails@claude-shared
```

Updates are not automatic for this marketplace by default: run `claude plugin marketplace update claude-shared`, then `claude plugin update claude-shared@claude-shared` (and the same for `guardrails`).

**Naming.** Plugin skills are namespaced: invoke them as `/claude-shared:github`, `/claude-shared:gitlab`, and so on. A same-named agent in `~/.claude/agents/` or a project's `.claude/agents/` overrides the plugin's, so remove old copied agent files after switching to the plugin.

**Hooks.** The plugins register their own hooks; do not also register the same scripts in `settings.json`, or they may run twice (for `limit-agent-spawns.sh` that halves the cap).

Running inside `claude-docker`? Enable the plugins in the container's settings too; the container installs them into its own `~/.claude/plugins`.

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
| `tech-lead` | opus | low | PR/MR reviewer and pragmatic generalist; cannot spawn subagents |

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
| `limit-agent-spawns.sh` (claude-shared) | `PreToolUse` on `Agent` and `Workflow` | Denies the 3rd subagent spawn per session and any `Workflow` run until the user raises the cap |
| `block-dangerous.sh` (guardrails) | `PreToolUse` on `Bash` | Blocks `rm -rf`, `git reset --hard`, force pushes, `DROP TABLE`/`DATABASE`, and piping `curl`/`wget` into a shell |
| `protect-files.sh` (guardrails) | `PreToolUse` on `Edit` and `Write` | Blocks edits to `.env*`, lockfiles, keys and certificates, Terraform state, `.claude/settings*.json`, and files under `.git/` or `secrets/` |

## Delegation Policy

Two rules apply across the agents, skills, and hook in this repo:

1. **PR/MR reviews run on Opus at low effort.** The `tech-lead` agent pins `model: opus` and `effort: low`; the `claude-shared:github` and `claude-shared:gitlab` skills route reviews to it. `/code-review low` is the fallback when the session model is already Opus (it runs on the session model; always type the level, a bare `/code-review` reuses the last level typed). Low effort yields fewer, high-confidence findings, which is what a review should be.
2. **At most 2 spawned agents per session without explicit approval.** `Workflow` runs always need approval. The `create-team` skill and the `tech-lead` agent (which cannot spawn at all) follow this in their instructions; `limit-agent-spawns.sh` enforces it. The hook denies with a message that tells Claude to stop and ask, and prints the command that raises the cap once you have approved.

Put the same two rules in your global `~/.claude/CLAUDE.md` so the main session follows them even when no agent or skill is loaded:

```markdown
## Reviews and Delegation
- PR/MR reviews run on Opus at low effort. Delegate to the `tech-lead` agent (pinned to `model: opus`, `effort: low`). Only use `/code-review low` when the session model is already Opus, and always type the level. One reviewer, no fan-out across files or dimensions.
- Never spawn more than 2 agents (Agent calls, team teammates, Workflow runs) in a session without my explicit approval. Ask first, listing what each agent would do. Workflow runs always need approval.
- Delegating a review to `tech-lead` counts as one of the 2.
```

## Contributing

1. Create or modify agent/skill files following the [Claude Code agent format](https://docs.anthropic.com/en/docs/claude-code/agents)
2. Run `claude plugin validate .` and `claude plugin validate plugins/guardrails`
3. Bump `version` in the affected `plugin.json` when the change should reach installed copies
4. Open a PR with your changes and get a review from a colleague before merging
5. After merging a version bump, tag the release with `claude plugin tag` (creates `<plugin>--v<version>`)
