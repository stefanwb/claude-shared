## Why

Today `claude-docker` can only reach Anthropic's hosted API, authenticated by a
subscription OAuth token persisted in the `claude-code-home` named volume. If
that endpoint has an outage there is no fallback, and there is no way to reach
other models the team already runs behind a self-hosted LiteLLM proxy. We need a
per-run opt-in that routes Claude Code through an Anthropic-Messages-compatible
LLM gateway — for outage redundancy and access to non-Anthropic backends —
without weakening the project's credentials-off-by-default posture.

## What Changes

- Add a provider-agnostic `--gateway` opt-in flag to `run.sh`, following the
  existing per-run credential-opt-in discipline (`--aws`/`--gh`/`--glab`/`--tfe`).
- When `--gateway` is set, forward from the host environment: `ANTHROPIC_BASE_URL`
  and `ANTHROPIC_AUTH_TOKEN` (Bearer auth to the gateway), plus optional model
  overrides (`ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
  `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
  `ANTHROPIC_DEFAULT_FABLE_MODEL`) and optional `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`.
  Non-Anthropic backends are selected purely by model id, since Claude Code speaks
  the Anthropic wire format to the gateway regardless of the routed model.
- **Credential isolation:** in `--gateway` mode the Anthropic subscription OAuth
  credential (`/root/.claude/.credentials.json`) MUST be absent from the sandbox,
  masked via the existing tmpfs/empty-mount precedent, so a session routed through
  a third-party gateway cannot read or exfiltrate the Anthropic token. Auth comes
  solely from the forwarded `ANTHROPIC_AUTH_TOKEN`. Session history elsewhere
  under `/root/.claude` still persists.
- Tag the active gateway opt-in via the existing `CLAUDE_DOCKER_FLAGS` statusline
  mechanism so a session visibly shows it is running against a gateway.
- Document the flag in `README.md`; verify behavior against the spec scenarios
  (manual/argv-level, per project convention — no committed test harness).

## Capabilities

### New Capabilities
- `llm-gateway`: Routing Claude Code through an Anthropic-Messages-compatible LLM
  gateway via a per-run `--gateway` opt-in — forwarding endpoint/auth/model env
  vars and isolating the Anthropic subscription credential while gateway auth is
  in effect.

### Modified Capabilities
- `external-cli-tools`: The "Credentials opt-in" requirement gains a new
  credential pathway — host `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` forwarding
  — which must follow the same per-run dedicated-flag opt-in discipline (no
  forwarding without `--gateway`).
- `persistent-session-storage`: The invariant that credentials always persist in
  the named volume gains a deliberate carve-out — in `--gateway` mode the
  Anthropic OAuth credential file is masked so it is neither used nor visible,
  while session/project history continues to persist.

## Impact

- `claude-docker/run.sh`: new flag parsing, env-var forwarding, credential
  masking, statusline tagging, and `--help` text.
- `claude-docker/README.md`: new gateway usage/security section.
- No image/Dockerfile changes; no new runtime dependencies; no new test harness.
  Behavior is unchanged unless `--gateway` is passed.
