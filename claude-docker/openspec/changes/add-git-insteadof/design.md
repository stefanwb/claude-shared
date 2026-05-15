## Context

claude-docker's credential opt-ins (`--gh`, `--glab`, `--aws`, `--tfe`,
and on the in-flight branch `--tofu`) follow a consistent pattern: each
flag mounts the matching CLI tool's config dir read-only and forwards
its token env vars. The pattern works perfectly for invocations of the
named tool — `gh pr list`, `glab issue view`, `aws sts
get-caller-identity`, `terraform login` — and breaks down the moment a
DIFFERENT tool (most commonly `git`, often spawned by tofu/terraform
init for module fetch) needs the same credential surface.

Real failure mode: a user runs `claude-docker --glab <repo>` to work on
an IaC repo that pulls modules from `sbp.gitlab.schubergphilis.com`. The
glab CLI works inside the container; `tofu init` does not, because the
git subprocess it spawns has no way to discover the GitLab token.

Workarounds users reach for today:

1. `git config --global url."https://oauth2:$TOKEN@<host>".insteadOf <host>`
   on the **host**, run the command, then `git config --global --unset` —
   touches global state, requires manual revert, very leak-prone.
2. The same `git config --global` **inside the container**, which
   persists in `claude-code-root` and is silently visible to subsequent
   no-flag sessions until manually unset — a real credential leak.
3. Per-repo `.git/config` insteadOf — non-leaking but per-repo busywork
   and gets accidentally committed if the user isn't careful.

This change closes the gap once, for any tool that shells out to git
inside the container, by reusing the existing flag's intent: if the
user is already opted-in to `--gh` or `--glab`, they have already
granted the container credential access to those hosts, so making `git`
also use those credentials matches the user's intent.

## Goals / Non-Goals

**Goals:**

- `git clone https://<host>/<priv>.git` Just Works inside the container
  whenever the matching `--gh` or `--glab` flag is set, with no extra
  user steps (no env vars, no per-repo config, no chmod).
- Token never persists across container exits — gone with the writable
  layer on `docker run --rm`.
- Symmetric treatment of `--gh` and `--glab` — same UX, same threat
  story, same on/off semantics.
- `glab auth token` host fallback so users who run glab interactively
  (the common case) don't need to manually export `GITLAB_TOKEN`.
- Sensible default for the common case: `github.com` / `gitlab.com`
  alone when host enumeration fails or returns nothing.

**Non-Goals:**

- SSH-based git auth (key/agent forwarding). Different security model;
  separate flag if ever wanted.
- Token rotation mid-session. The system git config is set once at
  entrypoint; rotated tokens require a container restart.
- Bitbucket, Gitea, Codeberg, or other forges. Each would need its own
  credential flag wired up; this PR scopes to existing `--gh`/`--glab`.
- Cross-host token reuse (use a GitHub token for a private GitLab,
  etc.) — explicitly insecure, never auto-injected.
- Persistent host enumeration cache. We re-enumerate on every container
  start; cost is negligible (single small YAML parse) and avoids
  staleness.

## Decisions

### D1: System-level git config (`/etc/gitconfig`), not user-level

The injected `insteadOf` rule is written via `git config --system`,
which writes to `/etc/gitconfig`. `/etc/gitconfig` lives in the image
overlay (writable layer), which `docker run --rm` discards on container
exit. Result: the token never persists across sessions, even via the
`claude-code-root` named volume (which mounts `/root/`, not `/etc/`).

The alternative — `git config --global` writing to `/root/.gitconfig` —
WOULD persist via `claude-code-root`, becoming a stealth credential
leak: a later session without `--gh`/`--glab` would silently inherit
the rewrite (and the token in it) until the named volume is recycled.
That is the exact failure mode the existing `/root/.config/gh/` and
`/root/.terraform.d/` tmpfs masks were designed to prevent. Writing to
the image layer instead of the named volume avoids the whole class.

Precedence note: `--local` > `--global` > `--system`. So a user who
prefers to maintain their own `~/.gitconfig` inside the container
(persisted via `claude-code-root`) with custom insteadOf rules can do
so and their config wins. The system-level injection is a default that
defers to user intent.

### D2: Entrypoint script, not run.sh-side injection

The injection runs inside the container at startup (entrypoint), not on
the host as part of `run.sh`. Two reasons:

1. The token must end up in `/etc/gitconfig` *inside* the container —
   doing that from `run.sh` would require either (a) baking the user's
   token into a temporary file on the host and bind-mounting it (token
   touches host disk, ugly), or (b) `docker exec`-ing after `docker
   run` (race condition: claude starts before exec completes).
2. The entrypoint sees the actual final container env vars and the
   actual `/etc/gitconfig` it needs to write — no impedance mismatch
   with how docker layers and run flags interact at startup.

The entrypoint is a small POSIX shell script (`sh`, not `bash`) so it
runs without depending on bash being on PATH or any non-builtin
binaries beyond `git`, `awk`, and `tr` (all already present).

### D3: `oauth2:<token>` as the URL username

Both GitHub and GitLab accept the pattern
`https://oauth2:<token>@<host>/...` for HTTPS git auth:

- **GitHub**: PATs are passed as the password; the username can be any
  non-empty string. `oauth2` is the convention GitHub Actions and
  many tools use.
- **GitLab**: `oauth2:<token>` is the official documented pattern for
  PAT-based HTTPS git auth.

Using `oauth2` for both keeps the entrypoint logic uniform. Personal
access tokens, OAuth tokens, and GitHub App installation tokens all
work in the password slot.

**Alternatives considered:**
- `x-access-token:<token>` for GitHub (the GitHub App pattern).
  Rejected — works only for App tokens, breaks PAT auth.
- `<token>:` (empty username). Rejected — some git versions emit
  warnings about empty username; less portable.

### D4: Host enumeration on the host (in run.sh), not in the container

The entrypoint inside the container does not have access to the host's
`~/.config/gh/hosts.yml` or `~/.config/glab-cli/config.yml` — those
live on the host. Two ways to expose host config to the container:

1. Bind-mount the config dirs. **Already done** by `--gh`/`--glab` — but
   the file owned by uid 1000 mode 0700 means root inside the
   container (with `CAP_DAC_OVERRIDE` dropped) cannot *read* the
   bind-mounted file. We can't rely on that.
2. Parse the config on the host and forward the result as env vars.
   Reads on the host work (the user is uid 1000); env vars are always
   readable inside the container. Chosen.

`run.sh` reads `~/.config/{gh/hosts.yml,glab-cli/config.yml}` with a
small awk one-liner extracting second-level keys (the hostnames in
both files share the same structure: hosts as top-level keys in
hosts.yml for gh, hosts as values under a `hosts:` key for glab),
joins with commas, and exports
`CLAUDE_DOCKER_{GITHUB,GITLAB}_HOSTS`. If parsing yields nothing (no
config file, unreadable, format change), the entrypoint falls back to
the canonical public host (`github.com` / `gitlab.com`).

**Alternatives considered:**
- *Run `gh auth status` / `glab auth status` on the host to enumerate.*
  Rejected — output format is human-oriented and not stable; awk
  parsing of YAML keys is more robust than scraping CLI output, and
  doesn't depend on the CLI being installed (helpful for users who
  ssh-deploy claude-docker without local gh/glab).
- *Skip enumeration entirely; only handle the public host.* Rejected —
  the original user complaint was specifically about
  `sbp.gitlab.schubergphilis.com`, which is exactly the self-hosted
  case enumeration is for.

### D5: `glab auth token` fallback for `--glab`, symmetric with `--gh`

The existing `--gh` block in `run.sh` (lines 201-210) already falls
back to `gh auth token` when neither `GH_TOKEN` nor `GITHUB_TOKEN` is
set on the host. `--glab` has no equivalent fallback today: users who
authenticated via `glab auth login` (the typical UX) and never
exported `GITLAB_TOKEN` get a silently-no-op `--glab`.

Adding the symmetric `glab auth token` fallback closes that gap. Same
silent-on-failure shape as the gh fallback (no error if glab is absent
or not logged in).

### D6: Defaults `github.com` and `gitlab.com` when enumeration is empty

If the host parse returns no hosts (no config, format change, etc.) and
a token is present (either env var or CLI fallback found one), the
entrypoint defaults to the canonical public host. Rationale: a user
who exports `GH_TOKEN` but has no local `gh` install is unambiguously
authorizing access to github.com; refusing to inject the rewrite would
break the "Just Works" promise for the most common case.

The default never applies to the wrong host: it kicks in only when
enumeration yields *nothing*, never when enumeration yields hosts that
don't include the public one.

## Risks / Trade-offs

- **Risk:** Injected token is visible to anyone with read access to
  `/etc/gitconfig` inside the container — namely the running claude
  agent and any of its subprocesses.
  → **Mitigation:** This is the same blast radius the env-var-forwarded
  token already has; we are not widening it. Documented in the
  threat-model bullet.

- **Risk:** A user who has manually configured custom `insteadOf`
  rules in `/root/.gitconfig` via `claude-code-root` will see those
  override our `/etc/gitconfig` defaults (precedence: --global >
  --system). This is intentional but worth flagging — a user who
  forgets they set up a custom rule might be confused when our
  rewrite "doesn't take effect".
  → **Mitigation:** Documented. `git config --show-origin --get-all
  url.<host>.insteadOf` debugs the precedence quickly.

- **Risk:** Token leak via `git config --system --list` in shell
  history / log output. Anything that dumps git config exposes the
  token in plaintext.
  → **Mitigation:** Same risk as forwarded env vars; no marginal
  increase. Tooling that logs `git config --list` was already a
  leak vector for the user's host `~/.gitconfig` token-bearing
  entries (e.g. cargo's credential helper).

- **Risk:** Host enumeration parsing breaks if `gh`/`glab` change
  their config format.
  → **Mitigation:** Default fallback to `github.com`/`gitlab.com`
  keeps the common case working. Parsing is best-effort by design.
  Regressions surface at upgrade time, not silently.

- **Trade-off:** The entrypoint adds ~30ms to container startup
  (small awk + git config invocations). Negligible vs the multi-second
  Claude Code startup.

## Migration Plan

Purely additive. A user not setting `--gh`/`--glab` sees no change. A
user already setting them gets the new behaviour automatically — the
injection is a no-op for HTTPS clones against non-matching hosts and
takes effect only for the hosts they were already authorized for.

Rollback is removing the COPY/ENTRYPOINT lines from the Dockerfile, the
`CLAUDE_DOCKER_*_HOSTS` and glab-fallback blocks from `run.sh`, and
the entrypoint script — all localized.

## Open Questions

- Should we also auto-mount `~/.gitconfig` from the host so user
  signing keys, credential helpers, and other git config travel into
  the container? Current answer: no — that's a much wider change with
  its own credential-helper-on-Linux-vs-macOS complications. Worth a
  separate proposal if there's demand.
- Should `--tfe` / `--tofu` also get the insteadOf treatment for
  `app.terraform.io`? Current answer: probably no — terraform/tofu
  fetch modules over git, not over the Terraform Cloud API, so the
  `--tfe` token doesn't authorize git operations against
  `app.terraform.io`. Out of scope.
- Should the entrypoint also seed `git config --system credential.helper
  store` pointing at a tmpfs file containing the token? Equivalent to
  insteadOf for clones, but useful for `git push`. Current answer:
  insteadOf already covers push (the rewrite applies to the remote
  URL, not just clone), so credential.helper is redundant. Skipping
  unless a real workflow needs it.
