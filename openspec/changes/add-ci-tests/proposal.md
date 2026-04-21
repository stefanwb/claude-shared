## Why

This repo ships agents, skills, and a Docker image that developers install directly (`cp agents/*.md ~/.claude/agents/`, `docker build claude-docker/`). Without CI, a malformed agent frontmatter, a `run.sh` regression, or a Dockerfile pin drift can merge silently and break downstream users on their next pull. Reviewers catch what they can on PRs but have no automated safety net.

## What Changes

- Add a GitHub Actions workflow at `.github/workflows/ci.yml` that runs on `pull_request` and `push` to `main` (plus `workflow_dispatch`), with `concurrency` set to cancel in-progress PR builds.
- Validate YAML frontmatter of `agents/*.md` (required: `name`, `description`, `model`) and `skills/*/SKILL.md` (required: `name`, `description`) against per-kind schemas.
- Lint `claude-docker/run.sh` with shellcheck and `claude-docker/Dockerfile` with hadolint.
- Build (do not push) `claude-docker/Dockerfile` in CI to catch pin drift, broken `RUN` layers, and upstream fetch failures.
- Include advisory (non-blocking) checks for markdown style and broken relative links, behind a permissive config.
- No changes to agent/skill content, `run.sh` logic, or the Docker image itself — this is additive tooling only.

## Capabilities

### New Capabilities

- `ci-pipeline`: GitHub Actions workflow that validates every PR and main push through static lint, frontmatter schema validation, and Dockerfile build verification.

### Modified Capabilities

_None._ Existing capabilities (`external-cli-tools`, `host-config-parity`, `multi-workspace-mounts`, `persistent-session-storage`) live under `claude-docker/openspec/` and describe subproject behaviour, which is unchanged.

## Impact

- **New files**: `.github/workflows/ci.yml`, a small frontmatter-schema validator (Python + `pyyaml`, ~20 lines), optional permissive `.markdownlint.yaml` and `lychee.toml` if advisory checks are enabled.
- **Existing code**: no modifications expected. Day-1 checks should pass clean on current content.
- **Contributor workflow**: PRs now blocked on green CI for the blocking job set. Failures surface before review, not after merge.
- **Shipped artifacts**: unchanged. CI tooling runs only in Actions — nothing added to `agents/`, `skills/`, or the Docker image.
- **Permissions**: workflow runs with default `contents: read`; no secrets or registry credentials required.
