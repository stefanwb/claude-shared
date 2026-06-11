## 1. Wrapper: runtime selection

- [x] 1.1 In `run.sh`, add a runtime-selection block after the `IMAGE` assignment: read `CLAUDE_DOCKER_RUNTIME`; if unset, force `podman` when `${0##*/}` matches `*podman*`; if still unset, auto-detect (`docker` if on PATH, else `podman`, else error); if set explicitly, error when the named runtime is not on PATH
- [x] 1.2 Replace the hardcoded `docker run …` final invocation with `"$RUNTIME" run …`, preserving every existing flag, mount, env, and `-w`/`$IMAGE`/`$CMD` argument in order
- [x] 1.3 Prefix the engine invocation with `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'` so Git Bash does not rewrite container-side paths; confirm the prefix is scoped to that single command (inert on macOS/Linux, no platform branch)
- [x] 1.4 Update the `print_help` heredoc: intro line mentions docker *or* podman and the runtime precedence + `claude-podman` alias; add a `CLAUDE_DOCKER_RUNTIME` row to the `Environment` block
- [x] 1.5 `bash -n claude-docker/run.sh` passes (will also be ShellCheck-gated in CI at severity=warning)

## 2. Parallel command: claude-podman

- [x] 2.1 Verify argv[0] dispatch: invoked as `claude-docker` → auto-detect; as `claude-podman` (or any `*podman*` basename) → forced podman (verified by isolating the `case "${0##*/}"` logic: `claude-docker`→auto, `claude-podman`→podman, `my-claude-podman-thing`→podman)
- [x] 2.2 Confirm no second script is introduced — `claude-podman` is `run.sh` under a second install name (symlink or copy)

## 3. Smoke tests (Windows / Git Bash + podman 5.8.2, WSL backend)

- [x] 3.1 Runtime present: `which podman` resolves, `docker` absent; auto-detect under the `claude-docker` name selects podman (verified: only podman on PATH, prior `docker: command not found` is resolved)
- [x] 3.2 Host-path format: `podman run -v "/c/Users/...:/data:ro" …` mounts correctly with MSYS conversion disabled — both `C:/Users/...` (cygpath -m) and `/c/Users/...` (MSYS) forms accepted; MSYS form chosen so no `cygpath` rewrite is needed (verified: file readable at `/data/README.md`)
- [x] 3.3 Container-path integrity: full invocation with `--security-opt no-new-privileges`, `--cap-drop ALL`, `-v $ws:/workspaces/<name>`, named volume `-v claude-code-root:/root`, `--tmpfs /root/.config/gh`, `-w /workspaces/<name>` runs and reports `pwd=/workspaces/<name>` (verified: previously failing `-w` path now resolves; `claude` present at `/usr/bin/claude`)
- [x] 3.4 Image short-name resolution: `podman run claude-code:local …` resolves the locally-built `localhost/claude-code:local` without a registry pull (verified)
- [x] 3.5 Interactive launch: `claude-docker` from Git Bash drops into Claude Code with working dir `/workspaces/claude-shared`, no `invalid option type` error, no `the input device is not a TTY` error (verified interactively by the reporter)

## 4. No-regression checks (docker path unchanged)

- [x] 4.1 With `docker` on PATH, auto-detect still selects `docker` first (verified statically: the `command -v docker` branch precedes the podman fallback and the argv[0] tier only forces podman, never docker)
- [x] 4.2 No existing flag, mount, env-forwarding, tmpfs-mask, statusline, or git-overlay behavior is altered — the only changed lines are the new selection block and the single `"$RUNTIME" run` invocation (verified by diff scope)

## 5. Documentation

- [x] 5.1 README Install: add `podman build` as an alternative to `docker build`; add a second `ln -s … ~/bin/claude-podman` install line; note `cp` instead of `ln -s` where symlinks are awkward (Windows/Git Bash)
- [x] 5.2 README: add a "Container runtime (docker / podman)" subsection documenting the three-tier precedence and the docker/podman/Windows matrix
- [x] 5.3 README: document the Windows / Git Bash specifics — `MSYS_NO_PATHCONV`/`MSYS2_ARG_CONV_EXCL` handling and the `winpty` fallback for the rare interactive-TTY error

## 6. Validation

- [x] 6.1 `claude-docker --help` round-trips: every wrapper flag in the help text still has a matching case arm and vice versa (no flags added or removed by this change)
- [ ] 6.2 `openspec validate add-podman-runtime --strict` exits 0 (run by a maintainer with the openspec CLI; not installed on the reporter's host)
