## 1. Scaffolding

- [x] 1.1 Create `.github/workflows/` and `.github/scripts/` directories
- [x] 1.2 Add `.markdownlint.yaml` at the repo root with MD013 and MD033 disabled
- [x] 1.3 Add `lychee.toml` at the repo root configured for `--offline` and relative links only

## 2. Frontmatter validator

- [x] 2.1 Write `.github/scripts/check-frontmatter.py` using `pyyaml` that globs `agents/*.md` and `skills/**/*.md`
- [x] 2.2 Validate each file has a YAML frontmatter block with required fields `name`, `description`, `model`; exit non-zero listing every offending file
- [x] 2.3 Run the script locally against the current tree and confirm it exits 0

## 3. Workflow: top-level shape

- [x] 3.1 Create `.github/workflows/ci.yml` with `name: CI` and triggers `pull_request` (branches: main), `push` (branches: main), and `workflow_dispatch`
- [x] 3.2 Add `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`
- [x] 3.3 Add workflow-level `permissions: { contents: read }`

## 4. Workflow: lint job

- [x] 4.1 Add `lint` job pinned to `ubuntu-latest` with `permissions: { contents: read }` and `actions/checkout@<sha>` (v4)
- [x] 4.2 Add shellcheck step using `ludeeus/action-shellcheck@<sha>` targeting `claude-docker/run.sh` at severity `warning`
- [x] 4.3 Add hadolint step using `hadolint/hadolint-action@<sha>` targeting `claude-docker/Dockerfile` with `failure-threshold: warning`
- [x] 4.4 Add frontmatter step: `python3 .github/scripts/check-frontmatter.py` (install `pyyaml` via `pip install pyyaml` or use a pinned setup-python action)
- [x] 4.5 Add markdownlint advisory step using `DavidAnson/markdownlint-cli2-action@<sha>` with `continue-on-error: true`
- [x] 4.6 Add lychee advisory step using `lycheeverse/lychee-action@<sha>` with `--offline` and `continue-on-error: true`

## 5. Workflow: docker-build job

- [x] 5.1 Add `docker-build` job pinned to `ubuntu-latest` with `permissions: { contents: read }`
- [x] 5.2 Gate the job with `paths:` filter for `claude-docker/**` and `.github/workflows/ci.yml` (use trigger-level `paths:` on `pull_request`/`push`, or a `paths-filter` step)
- [x] 5.3 Add `actions/checkout@<sha>` and `docker/setup-buildx-action@<sha>`
- [x] 5.4 Add `docker/build-push-action@<sha>` with `context: claude-docker`, `push: false`, `platforms: linux/amd64`, `cache-from: type=gha`, `cache-to: type=gha,mode=max`

## 6. Pin all actions by commit SHA

- [x] 6.1 Resolve the latest release SHA for every third-party action referenced in `ci.yml`
- [x] 6.2 Replace every `@vX` or `@main` reference with the full 40-character commit SHA plus a `# vX.Y.Z` comment

## 7. Verification

- [ ] 7.1 Open a draft PR adding the workflow and confirm the workflow runs against its own branch
- [ ] 7.2 Confirm `lint` passes on the current tree (shellcheck, hadolint, frontmatter)
- [ ] 7.3 Confirm `docker-build` succeeds (amd64) or is correctly skipped when `claude-docker/**` is untouched
- [ ] 7.4 Force a failure in each blocking check (temporary commit on a throwaway branch) to confirm each check is wired correctly, then revert
- [ ] 7.5 Confirm advisory checks surface warnings without failing the overall status
