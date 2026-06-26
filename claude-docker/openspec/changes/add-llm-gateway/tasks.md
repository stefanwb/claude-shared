## 1. Wrapper: --gateway flag and env forwarding

- [x] 1.1 In `run.sh`, add `WITH_GATEWAY=0` alongside the other `WITH_*` initializers and a `--gateway) WITH_GATEWAY=1 ;;` arm in the case statement
- [x] 1.2 Under `WITH_GATEWAY=1`, append the gateway vars to the `ENV_VARS` array so the existing `[ -n "${!v:-}" ]` filter forwards each only when set on the host: `ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL ANTHROPIC_DEFAULT_FABLE_MODEL CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` — mirror the `[ "$WITH_TFE" = "1" ] && ENV_VARS+=(...)` line
- [x] 1.3 Append `gateway` to `DOCKER_FLAGS` when `WITH_GATEWAY=1` so the statusline tag reflects the opt-in

## 2. Wrapper: Anthropic credential isolation

- [x] 2.1 When `WITH_GATEWAY=1`, stage an empty file (under the same temp-staging dir used for host-config parity) and append a read-only bind mount of it over `/root/.claude/.credentials.json` to `MOUNT_ARGS`, so the persisted OAuth token is masked while the rest of `claude-code-home` stays mounted. Comment points at the credential-isolation rationale
- [x] 2.2 Mask applied independent of `EPHEMERAL` (verified via stub harness: `--ephemeral --gateway` still emits the credential overlay mount and forwards env, and no `claude-code-home` named volume is mounted). Mount ordering relies on Docker's documented parent-first ordering so the nested file overlay wins over the volume — same mechanism as the existing settings.json/CLAUDE.md overlays
- [ ] 2.3 No-prior-login case: bind-mounting the staged empty file over a not-yet-existent `/root/.claude/.credentials.json` — Docker auto-creates the bind-mount target, so this is expected to be a no-op error-wise. **Needs real-Docker confirmation** (no daemon in the dev sandbox); covered by the design's open question and the manual e2e checks in 4.3/4.5

## 3. Wrapper: help text

- [x] 3.1 Added a `--gateway` row to the `print_help` heredoc matching the `--tfe` style (forwards `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` + model overrides; masks the Anthropic OAuth credential)
- [x] 3.2 `claude-docker --help` round-trips: `--gateway` present in both help text and the case statement (verified by flag-diff)

## 4. Verification against scenarios

No committed test file — matching the project convention (manual verification recorded here; the `llm-gateway` spec scenarios are the behavior contract). Argv-level checks below were verified during development by stubbing `docker` on PATH and inspecting the generated `docker run` arguments; checks that require inspecting state *inside* a live container need a real daemon (none in the dev sandbox).

- [x] 4.1 Env forwarding both directions: `--gateway` forwards `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN`; without the flag neither is forwarded (verified at argv level)
- [x] 4.2 Model overrides: `ANTHROPIC_MODEL` forwarded when set; `ANTHROPIC_DEFAULT_SONNET_MODEL` not forwarded when unset (verified — the `-e NAME` form means an unset var is absent, never an empty string)
- [x] 4.3 Credential isolation (argv level): `--gateway` emits the RO overlay over `/root/.claude/.credentials.json`; no-flag run does not. **Real-Docker e2e** (file actually empty inside container + `projects/` still readable) pending a daemon
- [ ] 4.4 Credential restored on a subsequent no-flag run (mask non-destructive) — **needs real Docker**; logically guaranteed since the overlay is a per-run mount that touches nothing in the volume
- [ ] 4.5 No prior login: `claude-docker --gateway ~/repo` starts cleanly with no `.credentials.json` in the volume — **needs real Docker** (see 2.3)
- [x] 4.6 Statusline tag: `--gateway` sets `CLAUDE_DOCKER_FLAGS` containing `gateway`; `--gh --gateway` includes both markers (verified at argv level)

## 5. Documentation

- [x] 5.1 Added a `--gateway` row to the **Credential opt-in** table in `README.md`, matching the `--tfe` voice (forwards endpoint/auth/model env vars; nothing forwarded without the flag)
- [x] 5.2 Extended the **Auth model** section: source is host env, Bearer auth via `ANTHROPIC_AUTH_TOKEN`, Anthropic OAuth credential masked for the session (covered in the new LLM gateway sub-section)
- [x] 5.3 Added an "LLM gateway workflow" sub-section: usage flow, model selection by id, the haiku/background-model caveat, and that gateway mode disables OAuth/`claude login`; also noted history stays unified for `claude --resume`
- [x] 5.4 Updated the **Threat model**: per-session exposure of the gateway key, plus a dedicated bullet on the `--gateway` Anthropic-credential isolation guarantee

## 6. Validation

- [x] 6.1 `openspec validate add-llm-gateway --strict` exits 0
- [ ] 6.2 ShellCheck `run.sh` clean at `--severity=warning` — **not run in dev sandbox** (no shellcheck/docker/pip available); additions mirror existing shellcheck-clean patterns (quoted expansions, guarded array appends) and `bash -n` passes. CI's lint job is the gate
- [x] 6.3 `--ephemeral --gateway` spot-check: env forwarding happens and the named-volume mount is skipped cleanly (verified at argv level)
