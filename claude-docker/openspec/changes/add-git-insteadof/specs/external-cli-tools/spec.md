## ADDED Requirements

### Requirement: --gh and --glab inject git insteadOf rewrites

When `--gh` is set and a GitHub token reaches the container (via host env var `GH_TOKEN` / `GITHUB_TOKEN`, or the existing `gh auth token` fallback in `run.sh`), the container's startup SHALL write a system-level git config rewrite of the form `git config --system url."https://oauth2:<TOKEN>@<HOST>".insteadOf "https://<HOST>"` for each authenticated GitHub host. The host list SHALL come from `CLAUDE_DOCKER_GITHUB_HOSTS` (a comma-separated env var populated by `run.sh` from `~/.config/gh/hosts.yml`); when that env var is empty or unset and a token is present, the entrypoint SHALL default to `github.com`. The same SHALL apply to `--glab` and `GITLAB_TOKEN` / `CLAUDE_DOCKER_GITLAB_HOSTS`, defaulting to `gitlab.com`. The rewrite SHALL be written via `git config --system` (i.e. to `/etc/gitconfig`), which lives in the container's writable layer and is discarded on `docker run --rm` exit — so the token MUST NOT persist across container exits via the `claude-code-root` named volume (which mounts `/root/`, not `/etc/`). The rewrite SHALL NOT override a user's own `git config --global` (`/root/.gitconfig`) entry — git's precedence (`--local > --global > --system`) means a persisted user config wins, preserving user intent.

#### Scenario: --gh with explicit token rewrites github.com

- **GIVEN** the host exports `GH_TOKEN=ghp_x`
- **WHEN** user runs `claude-docker --gh ~/repo`
- **THEN** inside the container, `git config --system --get-all url.https://oauth2:ghp_x@github.com.insteadOf` prints `https://github.com`
- **AND** `git clone https://github.com/<priv>/<repo>` succeeds without prompting for credentials

#### Scenario: --glab with explicit token rewrites enumerated hosts

- **GIVEN** the host exports `GITLAB_TOKEN=glpat_x`
- **AND** the host's `~/.config/glab-cli/config.yml` has `hosts:` entries for `gitlab.com` and `sbp.gitlab.schubergphilis.com`
- **WHEN** user runs `claude-docker --glab ~/repo`
- **THEN** inside the container, `git config --system --list` includes rewrites for both `https://gitlab.com` and `https://sbp.gitlab.schubergphilis.com`
- **AND** `git clone https://sbp.gitlab.schubergphilis.com/<priv>/<repo>` succeeds without prompting

#### Scenario: glab auth token host fallback when GITLAB_TOKEN unset

- **GIVEN** the host has `glab` installed and the user is authenticated (`glab auth status` succeeds) against at least one host enumerated in `~/.config/glab-cli/config.yml`
- **AND** neither `GITLAB_TOKEN` nor any other host env var is exported
- **WHEN** user runs `claude-docker --glab ~/repo`
- **THEN** `run.sh` walks the enumerated host list (or `gitlab.com` when enumeration is empty), invokes `glab auth token --hostname <host>` for each, and forwards the first non-empty result as `GITLAB_TOKEN` into the container
- **AND** the in-container insteadOf rewrite is applied as if the user had exported the token manually

#### Scenario: glab fallback finds self-hosted-only token

- **GIVEN** the user is logged in ONLY to a self-hosted GitLab (e.g. `sbp.gitlab.schubergphilis.com`, no `gitlab.com` auth) — `~/.config/glab-cli/config.yml` has only the self-hosted host under `hosts:`
- **AND** `GITLAB_TOKEN` is not exported on the host
- **WHEN** user runs `claude-docker --glab ~/repo`
- **THEN** `glab auth token --hostname sbp.gitlab.schubergphilis.com` returns the user's token and `run.sh` forwards it as `GITLAB_TOKEN`
- **AND** the entrypoint writes `git config --system url."https://oauth2:<token>@sbp.gitlab.schubergphilis.com".insteadOf "https://sbp.gitlab.schubergphilis.com"`
- **AND** plain `glab auth token` (no `--hostname`, which defaults to `gitlab.com`) would have returned empty — the host-aware fallback is what makes the self-hosted-only case work

#### Scenario: gh fallback finds GH Enterprise-only token

- **GIVEN** the user is logged in ONLY to a GitHub Enterprise host (e.g. `ghe.example.com`) — `~/.config/gh/hosts.yml` has only that host
- **AND** neither `GH_TOKEN` nor `GITHUB_TOKEN` is exported
- **WHEN** user runs `claude-docker --gh ~/repo`
- **THEN** `gh auth token --hostname ghe.example.com` returns the user's token and `run.sh` forwards it as `GH_TOKEN`
- **AND** the in-container insteadOf rewrite is applied for `https://ghe.example.com`

#### Scenario: glab auth token fallback is silent when glab is unavailable

- **GIVEN** neither `GITLAB_TOKEN` is set nor `glab` is on the host PATH (or `glab auth token` exits non-zero for every enumerated host)
- **WHEN** user runs `claude-docker --glab ~/repo`
- **THEN** the container starts without `GITLAB_TOKEN` set and no error is printed
- **AND** no insteadOf rewrite is injected for any GitLab host

#### Scenario: default host when CLAUDE_DOCKER_GITLAB_HOSTS is empty

- **GIVEN** a token is present in the container env (`GITLAB_TOKEN=glpat_x`)
- **AND** `CLAUDE_DOCKER_GITLAB_HOSTS` is unset (e.g. host config file is missing or unparseable)
- **WHEN** the entrypoint runs
- **THEN** `git config --system --get-all url.https://oauth2:glpat_x@gitlab.com.insteadOf` prints `https://gitlab.com`
- **AND** no other host rewrites are injected

#### Scenario: token does not leak across container exits

- **GIVEN** a prior container run completed with `--gh` and a real `GH_TOKEN` (system git config was written)
- **WHEN** a subsequent `claude-docker ~/repo` runs without `--gh`
- **THEN** `cat /etc/gitconfig` inside the second container shows no `url.*.insteadOf` entries
- **AND** no token from the prior session is readable inside the container

#### Scenario: user global config wins over system injection

- **GIVEN** a user has run `git config --global url.<custom>.insteadOf <upstream>` inside a previous `--gh` session, persisting to `/root/.gitconfig` via `claude-code-root`
- **AND** the user now runs `claude-docker --gh ~/repo` with a token that would inject a colliding `--system` rule
- **WHEN** `git config --get-all url.<upstream>.insteadOf` runs inside the container
- **THEN** the user's `--global` value wins (precedence rule), preserving their intent
- **AND** the `--system` rule remains in place but inactive for that key

#### Scenario: no opt-in flag means no insteadOf injection

- **GIVEN** no host token is exported and no opt-in flag is passed
- **WHEN** user runs `claude-docker ~/repo`
- **THEN** the entrypoint runs but injects no rewrites
- **AND** `git config --system --list` inside the container shows no `url.*.insteadOf` entries
