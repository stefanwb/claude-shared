## Why

`run.sh` hardcodes `docker run`, so the wrapper only works where a `docker`
binary is on PATH. Developers running [Podman](https://podman.io/) — the default
rootless engine on Windows (via `podman machine` + WSL) and a common drop-in on
Linux — cannot use claude-docker at all: the invocation fails with
`docker: command not found`.

A second, Windows-specific failure compounds it. Run from Git Bash (MINGW), the
MSYS path-translation layer rewrites container-side Unix paths in the engine's
argv — `/workspaces/<name>`, `-w`, `--add-dir`, `/root/...` — into Windows paths
before the native `podman.exe` / `docker.exe` sees them, producing
`Error: invalid option type "\Program Files\Git\workspaces\..."`. Even after
swapping the binary by hand, the wrapper is unusable on Windows.

We want one wrapper that drives docker *or* podman, works on macOS, Linux, and
Windows/Git Bash, and keeps the existing docker-on-macOS behavior byte-for-byte
unchanged for current users.

## What Changes

- **Runtime selection in `run.sh`** with a clear precedence:
  1. `CLAUDE_DOCKER_RUNTIME=docker|podman` — explicit override, always wins.
  2. argv[0] multi-call dispatch — when the script is invoked under a name
     containing `podman` (i.e. installed as `claude-podman`), force podman.
  3. Auto-detect — prefer `docker` when on PATH (the historical default), else
     fall back to `podman`; error only when neither exists.
- **Parallel `claude-podman` command** implemented as the *same* `run.sh`
  installed under a second name (symlink or copy). No second script to keep in
  sync; the name decides the engine. `claude-docker` keeps auto-detecting so it
  still works on podman-only hosts.
- **Windows / Git Bash path-mangling fix**: scope `MSYS_NO_PATHCONV=1` and
  `MSYS2_ARG_CONV_EXCL='*'` to the single engine invocation so container-side
  paths pass through verbatim. Host paths in MSYS form (`/c/Users/...`) are
  accepted by the engine as-is, so no `cygpath` rewrite is needed. Both vars are
  inert on macOS/Linux, so no platform branch is required.
- **Update `--help`** intro and the `Environment` block to document the runtime
  precedence, the `claude-podman` alias, and `CLAUDE_DOCKER_RUNTIME`.
- **Update README** Install section (podman build command, install both names)
  and add a "Container runtime" subsection covering selection precedence and the
  Windows/Git Bash notes (including the `winpty` fallback for interactive TTY).

Out of scope (deliberately): a native PowerShell port (the wrapper is run from
Git Bash, which is sufficient); `cygpath` host-path rewriting (unnecessary — the
engine accepts MSYS `/c/...` paths); unconditional `winpty` wrapping (it can
interfere with the full-screen TUI and is only needed in non-ConPTY consoles);
rootless-podman SELinux `:z`/`:Z` volume relabeling (not required on the
Windows/WSL or macOS backends; can be revisited if a SELinux-enforcing Linux
host reports denials).

## Capabilities

### New Capabilities

- `container-runtime`: defines runtime selection (override → argv[0] → auto-detect),
  the `claude-podman` multi-call alias, and the Windows/Git Bash path-conversion
  handling required for native `docker.exe`/`podman.exe`.

### Modified Capabilities

None. Existing flags, defaults, and the docker-on-macOS code path are unchanged;
all behavior here is additive.

## Impact

- **Code**: `claude-docker/run.sh` (runtime selection block; `"$RUNTIME" run`
  with the MSYS env prefix in place of the hardcoded `docker run`; `--help`
  text).
- **Docs**: `claude-docker/README.md` (Install + new "Container runtime"
  subsection).
- **Specs**: new `container-runtime` capability.
- **No breaking changes**: `claude-docker` on a docker host behaves exactly as
  before. Installing `claude-podman` is opt-in.
- **Dependencies**: none added. Relies on the engine already being installed.
