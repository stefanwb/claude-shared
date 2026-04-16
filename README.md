# Claude Code Shared Configurations

Shared [Claude Code](https://docs.anthropic.com/en/docs/claude-code) agents and skills for our team.

## Structure

```
agents/         # Custom agent definitions
skills/         # Custom skill definitions
claude-docker/  # Hardened Docker container for running Claude Code
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

### claude-docker

Run Claude Code in a hardened container with isolated filesystem access and `gh`/`glab`/`aws` pre-installed. See [`claude-docker/README.md`](claude-docker/README.md) for the quickstart.

## Available Agents

| Agent | Model | Description |
|-------|-------|-------------|
| `architect` | opus | Infrastructure and platform architecture authority |
| `cost-control-reviewer` | sonnet | FinOps and cost optimization specialist |
| `mission-critical-engineer` | sonnet | Hands-on implementer and debugger |
| `principal-engineer` | opus | System design and cross-cutting architectural decisions |
| `qa-pipeline-expert` | sonnet | Testing, linting, and CI/CD pipeline expert |
| `security-devils-advocate` | opus | Adversarial security reviewer |
| `tech-lead` | opus | Pragmatic generalist for day-to-day engineering decisions |

## Contributing

1. Create or modify agent/skill files following the [Claude Code agent format](https://docs.anthropic.com/en/docs/claude-code/agents)
2. Open a PR with your changes
3. Get a review from a colleague before merging
