## ADDED Requirements

### Requirement: Workflow triggers

The CI workflow SHALL run on pull requests targeting `main`, on pushes to `main`, and on manual `workflow_dispatch` invocations.

#### Scenario: Pull request opened against main

- **WHEN** a contributor opens a pull request targeting the `main` branch
- **THEN** the CI workflow runs and reports status checks on the pull request

#### Scenario: Commit pushed to main

- **WHEN** a commit is pushed directly to `main` (e.g., via merge)
- **THEN** the CI workflow runs against that commit

#### Scenario: Manual dispatch

- **WHEN** a maintainer triggers the workflow via the Actions UI or API with `workflow_dispatch`
- **THEN** the CI workflow runs on the selected ref without requiring a new commit

### Requirement: Cancel stale in-progress runs

The CI workflow SHALL cancel any in-progress run for the same git ref when a newer commit is pushed to that ref.

#### Scenario: New commit supersedes in-progress PR run

- **WHEN** a new commit is pushed to a branch whose previous commit still has a CI run in progress
- **THEN** the in-progress run is cancelled and a new run starts for the newer commit

### Requirement: Least-privilege permissions

The CI workflow SHALL declare `permissions: contents: read` at the workflow level and MUST NOT grant any write scope to the `GITHUB_TOKEN`.

#### Scenario: Workflow token has no write access

- **WHEN** the workflow runs
- **THEN** the `GITHUB_TOKEN` cannot modify repository contents, issues, pull requests, packages, or any other write-scoped resource

### Requirement: Shell script linting

The CI workflow SHALL fail the build if `shellcheck` reports any issue at severity `warning` or higher against `claude-docker/run.sh`.

#### Scenario: Shellcheck warning in run.sh

- **WHEN** a change introduces a shellcheck warning or error in `claude-docker/run.sh`
- **THEN** the `lint` job fails and the overall CI status is failure

#### Scenario: Clean run.sh

- **WHEN** `claude-docker/run.sh` has no shellcheck findings at warning level or higher
- **THEN** the shellcheck step succeeds

### Requirement: Dockerfile linting

The CI workflow SHALL fail the build if `hadolint` reports any issue at severity `warning` or higher against `claude-docker/Dockerfile`.

#### Scenario: Hadolint warning in Dockerfile

- **WHEN** a change introduces a hadolint warning or error in `claude-docker/Dockerfile`
- **THEN** the `lint` job fails and the overall CI status is failure

### Requirement: Agent and skill frontmatter validation

The CI workflow SHALL validate YAML frontmatter on agent and skill files and fail the build on any violation. Schemas differ by kind:

- Agent files (`agents/*.md`) MUST contain `name`, `description`, and `model`.
- Skill files (`skills/*/SKILL.md`) MUST contain `name` and `description`. Supporting files under a skill directory (examples, auxiliary docs) are NOT in scope.

Invalid YAML, a missing frontmatter block, or a missing required field MUST cause the job to fail with a message naming the offending file and the specific problem.

#### Scenario: Agent file missing required field

- **WHEN** a file under `agents/` is missing the `name`, `description`, or `model` frontmatter field
- **THEN** the `lint` job fails with an error naming the offending file and missing field

#### Scenario: Skill file missing required field

- **WHEN** a file at `skills/<name>/SKILL.md` is missing the `name` or `description` frontmatter field
- **THEN** the `lint` job fails with an error naming the offending file and missing field

#### Scenario: Skill file with malformed YAML

- **WHEN** a file at `skills/<name>/SKILL.md` has a YAML frontmatter block that cannot be parsed
- **THEN** the `lint` job fails with an error naming the offending file

#### Scenario: Skill support file without frontmatter is ignored

- **WHEN** a file under a skill directory that is not `SKILL.md` (e.g., example specs, auxiliary docs) has no frontmatter
- **THEN** the validator does not flag it

#### Scenario: All files valid

- **WHEN** every agent and skill file has valid YAML frontmatter including all required fields for its kind
- **THEN** the frontmatter validation step succeeds

### Requirement: Dockerfile build verification

The CI workflow SHALL build `claude-docker/Dockerfile` for `linux/amd64` without pushing the resulting image.

#### Scenario: Dockerfile builds successfully

- **WHEN** the `docker-build` job runs against an unchanged Dockerfile
- **THEN** the build completes successfully and no image is pushed to any registry

#### Scenario: Upstream pin drift breaks the build

- **WHEN** a sha256-pinned download in the Dockerfile no longer matches the upstream resource
- **THEN** the `docker-build` job fails and the overall CI status is failure

### Requirement: Path-gated Docker build

The `docker-build` job SHALL run only when a pull request or push modifies files under `claude-docker/**` or modifies the workflow file itself.

#### Scenario: PR touching only agents/

- **WHEN** a pull request modifies only files under `agents/`
- **THEN** the `docker-build` job is skipped and the overall CI status depends only on `lint`

#### Scenario: PR touching claude-docker/

- **WHEN** a pull request modifies any file under `claude-docker/`
- **THEN** the `docker-build` job runs

### Requirement: Advisory checks do not block merges

Advisory checks (markdown lint, offline relative-link check) SHALL run on every triggered workflow but MUST NOT cause the overall CI status to fail when they report issues.

#### Scenario: Markdown lint reports warnings

- **WHEN** markdown lint reports style warnings on a changed `.md` file
- **THEN** the warnings are reported in the job log but the overall CI status remains success

#### Scenario: Broken relative link detected

- **WHEN** the offline link check finds a broken relative link in a markdown file
- **THEN** the finding is reported in the job log but the overall CI status remains success

### Requirement: Third-party actions pinned by commit SHA

Every third-party action referenced in the CI workflow SHALL be pinned to a full commit SHA rather than a tag or branch name.

#### Scenario: New action added without SHA pin

- **WHEN** the workflow references a third-party action as `owner/action@v1` or `owner/action@main`
- **THEN** this violates the pinning requirement and MUST be rejected during review

#### Scenario: All actions SHA-pinned

- **WHEN** every non-GitHub-owned action uses a 40-character commit SHA
- **THEN** the pinning requirement is satisfied
