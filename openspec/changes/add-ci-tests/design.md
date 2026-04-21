## Context

The repo has no CI today. Artifacts are consumed by direct file copy (`cp agents/*.md ~/.claude/agents/`) or by building the local `claude-docker/` image, so a silent regression reaches developers on their next `git pull`. The change surface is mixed: markdown with YAML frontmatter, a bash script with bash-3.2 compatibility constraints, and a Dockerfile with sha256-pinned downloads that can drift upstream. The nested `claude-docker/openspec/` subproject is scoped to the Docker image only; this CI change sits at the repo root and covers all three surfaces.

## Goals / Non-Goals

**Goals:**

- Block merges on broken agents, skills, `run.sh`, or Dockerfile.
- Fast feedback: lint job under 3 min, Docker-build job under 5 min.
- Zero maintenance day 1 — all blocking checks pass on the current `main`.
- No secrets, no registry writes, no external API calls from CI.

**Non-Goals:**

- Running Claude or agents in CI (no API key handling).
- Publishing the Docker image to any registry.
- External HTTP link checking (too flaky).
- Image vulnerability scanning (belongs in a dedicated security pipeline).
- Complexity metrics or prose linting on agent markdown bodies.
- Validating `claude-docker/openspec/` via the `openspec` CLI (separate decision; out of scope).

## Decisions

### D1. GitHub Actions, single workflow file

One file, `.github/workflows/ci.yml`, with two parallel jobs: `lint` and `docker-build`. Rejected alternatives: split files per concern (churn for a small repo), reusable workflows (overkill with one consumer).

### D2. Triggers and concurrency

`on: pull_request` against `main`, `push` to `main`, and `workflow_dispatch` (manual re-runs). `concurrency: ci-${{ github.ref }}` with `cancel-in-progress: true` — cancels stale PR builds while still letting main pushes queue per-ref.

### D3. Docker build: amd64 only, no push

Use `docker/build-push-action@v6` with `push: false` and `platforms: linux/amd64`. ARM64 adds ~10x runtime via QEMU. The Dockerfile's arch-conditional sha256 pins mean most drift shows up on both arches, so amd64-only catches the common case. Revisit if arm64-specific drift ever ships.

### D4. Path-based gating of `docker-build`

`docker-build` runs only on changes matching `claude-docker/**` (plus the workflow file itself). Skipping the 3–5 min build on PRs that only touch `agents/` or `skills/` saves runner minutes without losing signal — the Dockerfile is self-contained in that directory.

### D5. Frontmatter validation: small Python script

A small script at `.github/scripts/check-frontmatter.py` using only `pyyaml`. Validates per-kind required fields:

- Agents (`agents/*.md`): `name`, `description`, `model`.
- Skills (`skills/*/SKILL.md` only — supporting files under a skill directory are out of scope): `name`, `description`.

Optional fields (`tools`, `color`, `memory`, `argument-hint`, etc.) are allowed but not required. Rejected: `check-jsonschema` + JSON Schema — more dependencies, more YAML to maintain, for two in-house schemas. The per-kind split was confirmed during implementation by running the script against the current tree — a single unified schema failed because skills legitimately have no `model` field.

### D6. Lint actions: shellcheck and hadolint

`ludeeus/action-shellcheck` (pinned by SHA) and `hadolint/hadolint-action` (pinned by SHA). Both run in the `lint` job. Installing via apt was considered and rejected — actions are simpler and already pinned.

### D7. Advisory (non-blocking) checks

`markdownlint-cli2` with a committed permissive config (`.markdownlint.yaml` disabling MD013 line-length and MD033 inline HTML) and `lychee --offline` for broken relative links. Both run with `continue-on-error: true` so they surface warnings without blocking merges. Rationale: current markdown is hand-maintained and clean; strict rules would churn without proportional signal. Reassess after one month of data.

### D8. Permissions

Workflow-level `permissions: contents: read`. No write scopes, no secrets, no registry credentials. Per-job `permissions:` blocks explicitly re-declare read-only.

### D9. Runner and caching

`ubuntu-latest` for both jobs. No explicit GHA cache layer — lint tools run fast enough via pre-installed binaries or actions, and the Docker build relies on `docker/build-push-action`'s native `cache-from: type=gha` / `cache-to: type=gha,mode=max`.

### D10. Action pinning

All third-party actions pinned by commit SHA, not tag. Tag hijacking is a known supply-chain risk and this repo has no Dependabot today — manual SHA pins are the minimum bar.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| amd64-only build misses an arm64-specific pin drift | Low probability given arch-conditional pins; escalate to QEMU build if a real arm64 regression ships |
| Advisory checks become noise and get ignored | Limit advisory set to markdown-lint + link-check; revisit scope after first month of signal |
| Path filter skips `docker-build` when a root-level change still affects the image | Dockerfile is self-contained in `claude-docker/`; extend `paths:` filter if this proves wrong |
| Pre-existing content fails a new blocking check | Audit confirmed current `run.sh`, Dockerfile, and frontmatter pass clean; run linters locally when authoring the CI PR to catch surprises |
| Action SHA pins go stale and miss security fixes | Add Dependabot config in a follow-up change; meanwhile, bump SHAs during dependency reviews |
| GHA minutes bill grows with team size | All jobs on `ubuntu-latest` (free for public repos); concurrency-cancel and path-filter keep minutes low |

## Migration Plan

1. Land a single PR containing `.github/workflows/ci.yml`, `.github/scripts/check-frontmatter.py`, `.markdownlint.yaml`, and `lychee.toml`.
2. Validate on the PR itself — the workflow runs against its own branch via `pull_request`.
3. If any blocking check fails on pre-existing content, fix the content (preferred) or downgrade the check to advisory before merging.
4. No rollback plan needed beyond reverting the workflow PR — no external systems depend on CI.

## Open Questions

1. **Markdown lint: include or drop?** — existing markdown is clean. Advisory with a permissive config is proposed; could be removed entirely to reduce surface. Decide during implementation review.
2. **`bats` tests for `run.sh`** — audit flagged this as the highest coverage gap (openspec specs exist without tests). Deferred to a follow-up change so this PR stays tight.
3. **`openspec validate` on `claude-docker/openspec/`** — the CLI is now installed globally for authoring this change, but whether it should run in CI depends on signal-per-cost. Evaluate after this change lands.
4. **Frontmatter script location** — `.github/scripts/` vs. a new `scripts/ci/` at the repo root. Picks one during implementation; no external dependency either way.
