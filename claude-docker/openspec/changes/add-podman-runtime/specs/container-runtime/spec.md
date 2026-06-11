## ADDED Requirements

### Requirement: Runtime selection

`run.sh` SHALL drive either `docker` or `podman` as the container runtime,
selected at invocation time with the following precedence (highest first):

1. The `CLAUDE_DOCKER_RUNTIME` environment variable, when set to `docker` or
   `podman`. An explicit value SHALL always win. If the named runtime is not on
   PATH, `run.sh` SHALL exit non-zero with an error naming the requested runtime.
2. The name the script is invoked as (`argv[0]` basename). When that basename
   contains the substring `podman`, the runtime SHALL be `podman`.
3. Auto-detection: `docker` when it is on PATH, otherwise `podman` when it is on
   PATH. If neither runtime is available, `run.sh` SHALL exit non-zero with an
   error instructing the user to install docker or podman or set
   `CLAUDE_DOCKER_RUNTIME`.

The selected runtime SHALL be used for the single `run` invocation; no other
behavior (mounts, env forwarding, named volumes, `--add-dir`, statusline, git
overlay) SHALL depend on which runtime was chosen.

#### Scenario: docker host keeps docker by default

- **GIVEN** `docker` is on PATH and `CLAUDE_DOCKER_RUNTIME` is unset
- **AND** the script is invoked as `claude-docker`
- **WHEN** the wrapper runs
- **THEN** the container is launched with `docker`

#### Scenario: podman-only host falls back to podman

- **GIVEN** `docker` is not on PATH but `podman` is
- **AND** `CLAUDE_DOCKER_RUNTIME` is unset
- **AND** the script is invoked as `claude-docker`
- **WHEN** the wrapper runs
- **THEN** the container is launched with `podman`

#### Scenario: explicit override wins over name and auto-detect

- **GIVEN** `CLAUDE_DOCKER_RUNTIME=docker` is exported
- **AND** the script is invoked as `claude-podman`
- **WHEN** the wrapper runs
- **THEN** the container is launched with `docker`

#### Scenario: requested runtime missing is a hard error

- **GIVEN** `CLAUDE_DOCKER_RUNTIME=podman` is exported
- **AND** `podman` is not on PATH
- **WHEN** the wrapper runs
- **THEN** the wrapper exits non-zero
- **AND** prints an error naming the requested runtime
- **AND** does not attempt to launch a container

#### Scenario: no runtime available is a hard error

- **GIVEN** neither `docker` nor `podman` is on PATH
- **AND** `CLAUDE_DOCKER_RUNTIME` is unset
- **WHEN** the wrapper runs
- **THEN** the wrapper exits non-zero with an instruction to install a runtime
  or set `CLAUDE_DOCKER_RUNTIME`

### Requirement: claude-podman parallel command

The wrapper SHALL be installable under a second name, `claude-podman`, that
forces the podman runtime. This SHALL be the same `run.sh` file installed under
the second name (via symlink or copy), not a separate script. Forcing podman
SHALL be achieved solely through the `argv[0]` tier of runtime selection, so the
two names share one implementation.

#### Scenario: claude-podman forces podman regardless of docker presence

- **GIVEN** `run.sh` is installed as both `claude-docker` and `claude-podman`
- **AND** `docker` is on PATH
- **AND** `CLAUDE_DOCKER_RUNTIME` is unset
- **WHEN** the user runs `claude-podman ~/repo`
- **THEN** the container is launched with `podman`

#### Scenario: prefixed or suffixed install name still dispatches to podman

- **GIVEN** the script is invoked under a name whose basename contains `podman`
  (e.g. `my-claude-podman`)
- **AND** `CLAUDE_DOCKER_RUNTIME` is unset
- **WHEN** the wrapper runs
- **THEN** the runtime is `podman`

### Requirement: Windows / Git Bash path handling

When the wrapper invokes a native `docker.exe`/`podman.exe` from Git Bash
(MINGW), the MSYS path-conversion layer SHALL NOT rewrite container-side Unix
paths in the engine's arguments. `run.sh` SHALL scope `MSYS_NO_PATHCONV=1` and
`MSYS2_ARG_CONV_EXCL='*'` to the single engine invocation. These variables are
inert on macOS/Linux, so the wrapper SHALL NOT require a platform branch to set
them. Host paths in MSYS form (`/c/Users/...`) SHALL be passed to the engine
unmodified; the wrapper SHALL NOT perform `cygpath` rewriting of host paths.

#### Scenario: container-side paths are not mangled from Git Bash

- **GIVEN** the wrapper is run from Git Bash (MINGW) with a native
  `podman.exe`/`docker.exe`
- **WHEN** the engine is invoked with container-side paths such as
  `-w /workspaces/<name>`, `-v <host>:/workspaces/<name>`, and
  `--add-dir /workspaces/<other>`
- **THEN** those paths reach the engine verbatim (no rewrite to a Windows path
  such as `C:\Program Files\Git\workspaces\<name>`)
- **AND** the container's working directory is `/workspaces/<name>`

#### Scenario: MSYS-form host path mounts correctly

- **GIVEN** a host workspace whose absolute path in MSYS form is `/c/Users/...`
- **WHEN** the wrapper mounts it with `-v "/c/Users/...:/workspaces/<name>"`
- **THEN** the workspace contents are readable at `/workspaces/<name>` inside
  the container without any `cygpath` conversion of the host path
