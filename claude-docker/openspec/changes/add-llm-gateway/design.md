## Context

`claude-docker`'s `run.sh` wraps `docker run` and is the single place where host
credentials, mounts, and env vars are granted to the container. Today it has no
notion of the model endpoint: Claude Code defaults to `api.anthropic.com` and
authenticates with a subscription OAuth token that lives in `/root/.claude/.credentials.json`
inside the `claude-code-home` named volume (mounted at run.sh:395). The wrapper
forwards only a curated allowlist of env vars (run.sh:195-205) and already has a
"mask persisted state when its opt-in is off" pattern using tmpfs overlays
(run.sh:391-393). This change adds a model-endpoint pathway that fits those
existing mechanisms rather than inventing new ones.

Claude Code talks the Anthropic Messages wire format to whatever
`ANTHROPIC_BASE_URL` points at, so a LiteLLM gateway can front non-Anthropic
backends transparently — model choice is just a model id. `ANTHROPIC_AUTH_TOKEN`
(Bearer) takes precedence over the OAuth credential, so functionally the gateway
is used once the env vars are set; the credential masking is a defense-in-depth
requirement, not a functional one.

## Goals / Non-Goals

**Goals:**
- A per-run `--gateway` opt-in that forwards endpoint/auth/model env vars from the
  host into the container, consistent with the `--aws`/`--gh`/`--glab`/`--tfe`
  opt-in discipline.
- Guarantee the Anthropic subscription credential is absent from the sandbox
  whenever `--gateway` is active, so a session routed through a third-party
  gateway cannot read or exfiltrate it.
- Preserve session/project history persistence in gateway mode.
- Provider-agnostic naming and docs (gateway, not "litellm"/"anthropic failover").

**Non-Goals:**
- Running or configuring the LiteLLM gateway itself (infra outside this repo).
- Auto-detecting or defaulting an endpoint — the user supplies host env vars.
- Bedrock/Vertex native modes (`CLAUDE_CODE_USE_BEDROCK`/`_VERTEX`); those are a
  separate pathway and out of scope.
- Persisting a separate gateway credential store across runs.

## Decisions

### Flag name: `--gateway`
Provider-agnostic; frames the feature as "route through an LLM gateway" rather
than naming today's specific tool. Alternatives considered: `--litellm` (ties the
interface to one implementation) and `--proxy` (overloaded with HTTP/network
proxy). Rejected both.

### Env forwarding reuses the existing allowlist loop
Add the gateway vars to the same `ENV_VARS`/`ENV_ARGS` mechanism (run.sh:195-205)
guarded by a `WITH_GATEWAY` flag. Each var forwards only when set on the host
(the existing `[ -n "${!v:-}" ]` guard), so unset model overrides never become
empty strings in the container. Forwarded vars: `ANTHROPIC_BASE_URL`,
`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
`ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
`ANTHROPIC_DEFAULT_FABLE_MODEL`, `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`.

### Credential masking: empty read-only file over the credential path
The existing masks use `--tmpfs` over a directory (e.g. `/root/.config/gh`). The
Anthropic credential is a single file inside the `claude-code-home` volume, so a
directory tmpfs is the wrong granularity — tmpfs-ing `/root/.claude` would hide
session history too. Instead, when `WITH_GATEWAY=1`, stage an empty file and
bind-mount it read-only over `/root/.claude/.credentials.json`. This masks only
the credential, leaves `/root/.claude/projects/` and other config intact, and is
non-destructive (the underlying volume file is untouched and reappears on a
non-gateway run). The staged file is created under the same temp-staging approach
the script already uses for host-config parity (run.sh ~253+), so Colima/virtiofs
mount quirks are handled identically.

Alternative considered: bind-mounting `/dev/null` over the file. Rejected as
hacky and platform-fragile compared to an empty staged file.

Edge case: if `.credentials.json` does not yet exist in the volume (fresh
install, never logged in), bind-mounting over a non-existent target can error on
some Docker backends. The implementation stages the empty file and mounts it;
Docker creates the mountpoint for bind mounts, so this is expected to be a no-op.
Confirm both the "credential present" and "no prior login" cases against a real
daemon during verification.

### Statusline tag via `CLAUDE_DOCKER_FLAGS`
Append `gateway` to the `DOCKER_FLAGS` array (run.sh:241-251) when `WITH_GATEWAY=1`
so the statusline visibly marks the session — important because the session may be
hitting a non-Anthropic model and the user should see that at a glance.

## Risks / Trade-offs

- **Token still readable by the user before launch (it's their own host env).** →
  Expected; the isolation goal is about the *sandbox/session* not holding the
  Anthropic subscription token, not about hiding the gateway token from its owner.
- **Masking the credential breaks `claude login` / OAuth refresh while in gateway
  mode.** → Intended: gateway mode authenticates solely via `ANTHROPIC_AUTH_TOKEN`.
  Documented in the README; users wanting OAuth simply omit `--gateway`.
- **Bind-mount over a missing credential file errors on some backends.** → Stage
  the empty file and rely on Docker creating the mountpoint; confirm the
  no-prior-login path against a real daemon during verification.
- **Model override misconfiguration (gateway lacks a haiku-class model) causes
  background calls to fail.** → Out of scope to fix here, but documented: point
  `ANTHROPIC_DEFAULT_HAIKU_MODEL` at a model the gateway actually serves.
- **Forwarding an auth token by default would cut against credentials-off-by-default.**
  → Mitigated by gating all forwarding behind the explicit `--gateway` flag;
  verified that nothing is forwarded without it.

## Migration Plan

Additive and opt-in; no migration. Existing invocations behave identically
because all new behavior is gated on `--gateway`. Rollback is removing the flag
branch. To adopt: export `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` (and any
model overrides) on the host, then run `claude-docker --gateway <workspace>`.

## Open Questions

- None blocking. The exact behavior of bind-mounting over a non-existent
  `.credentials.json` will be confirmed empirically against a real Docker daemon
  during verification.
