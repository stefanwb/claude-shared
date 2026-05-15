## Why

`--gh` and `--glab` today forward the **CLI tool's** credentials (the `gh`
and `glab` binaries authenticate; tokens reach the container via env
vars + mounted config dirs). They do **not** teach in-container `git` how
to authenticate against the corresponding private HTTPS hosts. This
breaks every workflow where a tool inside the container shells out to
git to fetch a private repo:

- `tofu init` / `terraform init` pulling private GitLab or GitHub module sources
- `go get` / `cargo` / `pip` fetching private VCS deps
- `git clone https://sbp.gitlab.schubergphilis.com/<priv>.git` directly

Real failure mode observed: a user passes `claude-docker --glab` to work
on an IaC repo, in-container `tofu init` shells out to git for module
fetch, and git fails with `could not read Username for
sbp.gitlab.schubergphilis.com`. The fix users reach for today is `git
config --global url."https://oauth2:$TOKEN@<host>".insteadOf <host>` —
either inside the container (where it persists in `claude-code-root`
and leaks credentials into future no-flag sessions) or on the host
(where it touches global config with a token, then has to be
immediately reverted to avoid persistence). Neither is great hygiene.

A second, smaller gap: `--gh` has a `gh auth token` host-side fallback
for users who haven't exported `GH_TOKEN`, but `--glab` does not. Users
who use glab interactively (the common case) and never export
`GITLAB_TOKEN` get a silently-no-op `--glab`.

## What Changes

- **Add `glab auth token` host fallback to `--glab`**, mirroring the
  existing `--gh` fallback for `gh auth token`. Silent on failure (glab
  not on host PATH, not logged in).
- **Enumerate authenticated hosts on the host** from `~/.config/gh/hosts.yml`
  and `~/.config/glab-cli/config.yml` and forward them as
  `CLAUDE_DOCKER_GITHUB_HOSTS` / `CLAUDE_DOCKER_GITLAB_HOSTS` env vars
  (comma-separated). Defaults to `github.com` / `gitlab.com` when the
  config file is missing or unreadable, so the common case Just Works
  without enumeration.
- **Add a container entrypoint** (`/usr/local/bin/claude-docker-entrypoint`)
  that, before exec-ing the supplied CMD, reads the forwarded tokens
  and host lists and writes `git config --system url."https://oauth2:$TOKEN@<host>".insteadOf "https://<host>"`
  for each authenticated host. The `--system` config writes to
  `/etc/gitconfig`, which is part of the image-layer overlay and is
  discarded on `docker run --rm` exit (run.sh always uses `--rm`) — so
  there is **no cross-session credential leakage** via the
  `claude-code-root` named volume.
- **Update README** to document the auto-injection behaviour under
  `--gh` and `--glab` in the Auth model section, and add a "Private git
  module fetch" subsection covering the standard usage flow and its
  HTTPS-only scope.

Out of scope (deliberately):
- SSH-based git auth. Forwarding an SSH agent socket (or worse, a
  private key) into the container is a much wider threat surface and
  isn't symmetric with the existing `--gh`/`--glab` HTTPS posture.
- Token rotation during long-running sessions. `git config --system` is
  set once at startup; if the host token rotates mid-session, the
  in-container git config goes stale. Re-launch the container.
- Per-repo `.git/config` rewrites. The system-level rewrite covers every
  repo touched in the session — simpler and matches user intent
  ("anything I git-clone in this session against $HOST uses my $TOKEN").
- Self-hosted Bitbucket / Gitea / etc. The opt-in shape is keyed on the
  matching credential flag (`--gh`/`--glab`); a Bitbucket fix would
  need its own `--bb` flag, out of scope here.

## Capabilities

### New Capabilities

None. This change extends an existing capability.

### Modified Capabilities

- `external-cli-tools`: the `--gh` and `--glab` opt-ins gain (a) a host
  fallback that runs `gh auth token` / `glab auth token` to discover
  the token when no env var is set, (b) host enumeration via
  `CLAUDE_DOCKER_{GITHUB,GITLAB}_HOSTS` env vars, and (c) auto-injection
  of in-container `git config --system url.insteadOf` rewrites at
  container startup so in-container `git` can authenticate against the
  same hosts the matching CLI tool can. The "credentials opt-in" and
  "no creds reach the container without an explicit flag" invariants
  are preserved — the new behaviour only fires when the corresponding
  flag is set.

## Impact

- **Code**: new `claude-docker/entrypoint.sh` (small POSIX shell
  script); `claude-docker/Dockerfile` (COPY + chmod + ENTRYPOINT);
  `claude-docker/run.sh` (glab token fallback + host enumeration +
  env-var forwarding).
- **Docs**: `claude-docker/README.md` (Auth model rows for
  `--gh`/`--glab` extended; new "Private git module fetch" subsection;
  threat-model bullet on the injected token's blast radius).
- **Specs**: delta to `external-cli-tools`.
- **No breaking changes.** A user who passes `--gh` or `--glab` today
  with no private-git workflow sees identical behaviour: the
  insteadOf injection is a no-op for HTTPS clones against
  non-matching hosts. A user who has manually configured insteadOf in
  `~/.gitconfig` inside the container (via `claude-code-root`)
  overrides the system-level injection (--global wins over --system),
  preserving their setup.
- **Dependencies**: no new binaries. Uses already-installed `git`,
  `gh`, `glab`, and `awk`/`sh` for the entrypoint and host parsing.
