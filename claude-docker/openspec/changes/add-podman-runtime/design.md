## Context

`run.sh` ends in a hardcoded `docker run …`. The image, the named volumes, the
bind-mount logic, and the `claude` invocation are all engine-agnostic — only the
final exec line names the engine. Two distinct failures block non-docker and
Windows users:

1. **No docker binary.** Podman is the default rootless engine on Windows
   (`podman machine` + WSL backend) and a common Linux drop-in. The wrapper
   fails immediately with `docker: command not found`.
2. **MSYS path mangling.** From Git Bash (MINGW), the MSYS layer auto-translates
   Unix-looking argv into Windows paths when it spawns a *native* `.exe`. The
   container-side paths the wrapper builds (`/workspaces/<name>`, `-w`,
   `--add-dir`, `/root/...`) get rewritten to e.g.
   `C:\Program Files\Git\workspaces\<name>`, and the engine rejects them
   (`invalid option type`).

Both were reproduced on a real Windows host: Git Bash, podman 5.8.2, WSL backend.

## Goals / Non-Goals

**Goals:**

- One wrapper drives docker or podman, selected predictably.
- A parallel `claude-podman` command that forces podman on any OS, without a
  second script to maintain.
- Works from Git Bash on Windows with native `podman.exe`.
- Zero behavior change for existing docker-on-macOS/Colima users.

**Non-Goals:**

- A native PowerShell port. The wrapper runs from Git Bash, which is sufficient
  and keeps a single implementation.
- `cygpath` host-path rewriting (proven unnecessary — see D3).
- Unconditional `winpty`. It can corrupt the full-screen TUI and is only needed
  in legacy non-ConPTY consoles.
- SELinux `:z`/`:Z` volume relabeling. Not required on the WSL or macOS
  backends; revisit only if an SELinux-enforcing Linux host reports denials.

## Decisions

### D1: Three-tier runtime selection (override → argv[0] → auto-detect)

```
CLAUDE_DOCKER_RUNTIME set? ── yes ─→ use it (error if not on PATH)
        │ no
argv[0] contains "podman"? ── yes ─→ podman
        │ no
docker on PATH? ── yes ─→ docker ── no ─→ podman on PATH? ── yes ─→ podman ── no ─→ error
```

The explicit env var is the escape hatch and always wins. The argv[0] tier is
what makes `claude-podman` work. Auto-detect preserves the historical
docker-first default while letting the default `claude-docker` name still run on
podman-only hosts (the common Windows case).

**Alternatives considered:**
- *Replace docker with podman outright.* Rejected — breaks every existing
  macOS/Colima user.
- *A `--podman` flag instead of a second command name.* Rejected — the user
  asked for a parallel command, and a command name is more discoverable and
  composes with shell `alias`/PATH than a flag that must precede every run.

### D2: `claude-podman` is the same `run.sh`, dispatched by argv[0]

Classic multi-call (busybox-style) pattern: install `run.sh` under both names
(symlink or copy) and branch on `${0##*/}`. Matching on the substring `podman`
(not exact equality) tolerates prefixed/suffixed install names. This avoids a
second script that would inevitably drift from the ~400-line original.

**Alternatives considered:** a thin `claude-podman` wrapper that `exec`s
`CLAUDE_DOCKER_RUNTIME=podman run.sh`. Rejected — a second file to install and
keep in sync for no benefit over an argv[0] check.

### D3: Disable MSYS path conversion; do *not* rewrite host paths

Scope `MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL='*'` to the single engine
invocation. This stops MSYS from touching the container-side paths. Verified on
the target host that podman accepts host paths in MSYS form (`/c/Users/...`)
directly, so the existing `abs=$(cd "$ws" && pwd)` output works unmodified — no
`cygpath -w/-m` conversion is needed. Both vars are no-ops on macOS/Linux, so
the line needs no platform branch and the rest of the script (which calls MSYS
builtins like `cp`/`git`, not native exes) is unaffected because the prefix is
scoped to just the engine command.

**Alternatives considered:**
- *Set the vars globally at the top of the script.* Rejected — wider blast
  radius than needed; scoping to the one native-exe call is precise.
- *`cygpath`-convert every host path to `C:/...`.* Rejected — adds Windows-only
  code and a dependency for a conversion the engine doesn't require.

### D4: Interactive TTY handled by docs, not code

`claude` is launched with `-it`. Native `podman.exe`/`docker.exe` under Windows
Terminal (ConPTY) attach to the console directly and work. The legacy MSYS-pty
`the input device is not a TTY` case is rare and its fix (`winpty`) can itself
break full-screen TUIs, so it is documented as a fallback rather than forced on.

## Risks / Trade-offs

- **Risk:** argv[0] substring match on `podman` is loose — a repo or workspace
  arg never reaches it (it matches only the script's own invocation name), so
  the only "collision" would be deliberately naming the install `…podman…`,
  which is exactly the intent.
  → **Mitigation:** none needed; the match is on `$0`, not user arguments.

- **Risk:** A future Windows host on a non-ConPTY console hits the TTY error.
  → **Mitigation:** documented `winpty` fallback in the README.

- **Trade-off:** Auto-detect prefers docker, so on a host with *both* engines
  installed `claude-docker` picks docker. Users who want podman there use
  `claude-podman` or `CLAUDE_DOCKER_RUNTIME=podman`.

## Migration Plan

Purely additive. `claude-docker` on a docker host is byte-for-byte unchanged in
behavior. Installing `claude-podman` is opt-in. Rollback is reverting `run.sh`
to the hardcoded `docker run` line and dropping the second install name.

## Open Questions

- Should auto-detect prefer the engine matching `CLAUDE_DOCKER_IMAGE`'s registry
  prefix (e.g. `localhost/` favors podman)? Deferred — no evidence it's needed;
  the explicit override and the `claude-podman` name already cover intent.
