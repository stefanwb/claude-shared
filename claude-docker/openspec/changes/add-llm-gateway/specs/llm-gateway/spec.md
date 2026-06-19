## ADDED Requirements

### Requirement: Gateway opt-in routes Claude Code through a custom endpoint

`run.sh` SHALL support a `--gateway` flag that opts the session into routing
Claude Code through an Anthropic-Messages-compatible LLM gateway (e.g. a
self-hosted LiteLLM proxy) instead of the default Anthropic API. The flag is off
by default; without it, no gateway env vars reach the container and behavior is
unchanged.

When `--gateway` is set, `run.sh` SHALL forward the following host environment
variables into the container when they are set on the host:

- `ANTHROPIC_BASE_URL` — the gateway endpoint.
- `ANTHROPIC_AUTH_TOKEN` — Bearer credential presented to the gateway.
- model overrides `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_OPUS_MODEL`,
  `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
  `ANTHROPIC_DEFAULT_FABLE_MODEL`.
- `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`.

A host variable that is unset SHALL be silently skipped (not forwarded as empty).

#### Scenario: --gateway forwards endpoint and auth

- **GIVEN** the host exports `ANTHROPIC_BASE_URL=https://litellm.internal:4000` and `ANTHROPIC_AUTH_TOKEN=sk-gw-xyz`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** `echo $ANTHROPIC_BASE_URL` inside the container prints `https://litellm.internal:4000`
- **AND** `echo $ANTHROPIC_AUTH_TOKEN` inside the container prints `sk-gw-xyz`

#### Scenario: model overrides forwarded when set

- **GIVEN** the host exports `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, and `ANTHROPIC_MODEL=my-gateway-model`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** `echo $ANTHROPIC_MODEL` inside the container prints `my-gateway-model`

#### Scenario: unset gateway vars are not forwarded as empty

- **GIVEN** the host exports `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` but does not set `ANTHROPIC_MODEL`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** `ANTHROPIC_MODEL` is unset inside the container (not defined as an empty string)

#### Scenario: no gateway forwarding without the flag

- **GIVEN** the host exports `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`
- **WHEN** the user runs `claude-docker ~/repo` without `--gateway`
- **THEN** `echo $ANTHROPIC_BASE_URL` inside the container is empty
- **AND** `echo $ANTHROPIC_AUTH_TOKEN` inside the container is empty

### Requirement: Anthropic subscription credential is isolated in gateway mode

In `--gateway` mode `run.sh` SHALL mask the Anthropic subscription OAuth
credential persisted at `/root/.claude/.credentials.json` (in the
`claude-code-home` named volume) so it is neither used nor readable inside the
sandbox, even though the named volume is otherwise mounted. Authentication to the
model endpoint SHALL come solely from the forwarded `ANTHROPIC_AUTH_TOKEN`.
Session and project history elsewhere under `/root/.claude` SHALL continue to
persist.

#### Scenario: OAuth credential absent under --gateway

- **GIVEN** a prior non-gateway run completed `claude login`, persisting `/root/.claude/.credentials.json` in `claude-code-home`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** `/root/.claude/.credentials.json` inside the container is empty or absent (contains no usable token)

#### Scenario: session history still persists under --gateway

- **GIVEN** a prior run left session files under `/root/.claude/projects/`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** the prior session files under `/root/.claude/projects/` remain readable

#### Scenario: OAuth credential restored when gateway not used

- **GIVEN** a prior run completed `claude login`, persisting the credential
- **WHEN** the user runs `claude-docker ~/repo` without `--gateway`
- **THEN** `/root/.claude/.credentials.json` inside the container contains the persisted token

### Requirement: Active gateway opt-in is surfaced in the statusline

When `--gateway` is active, `run.sh` SHALL include a `gateway` marker in the
`CLAUDE_DOCKER_FLAGS` value so the statusline tags the session as running against
a gateway.

#### Scenario: gateway tag present

- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** the `CLAUDE_DOCKER_FLAGS` env var inside the container contains `gateway`
