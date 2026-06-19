## MODIFIED Requirements

### Requirement: Sessions persist across container runs

All Claude session files, credentials, and project records SHALL live in a named Docker volume that survives `--rm` container lifecycles. As a deliberate exception, when the `--gateway` opt-in is active the Anthropic subscription OAuth credential at `/root/.claude/.credentials.json` SHALL be masked so it is neither used nor readable in that session, while session and project records under `/root/.claude/projects/` SHALL continue to persist as normal. The masking does not delete the persisted credential; it is hidden only for the duration of gateway-mode runs and is visible again on a subsequent non-gateway run.

#### Scenario: Sessions survive exit

- **WHEN** the user exits a Claude session and relaunches the container
- **THEN** prior session files under `/root/.claude/projects/` remain readable

#### Scenario: Gateway mode masks the Anthropic credential but keeps history

- **GIVEN** a prior non-gateway run persisted `/root/.claude/.credentials.json` and session files under `/root/.claude/projects/`
- **WHEN** the user runs `claude-docker --gateway ~/repo`
- **THEN** `/root/.claude/.credentials.json` inside the container contains no usable token
- **AND** the prior session files under `/root/.claude/projects/` remain readable

#### Scenario: Credential reappears on a non-gateway run

- **GIVEN** a prior gateway-mode run masked the Anthropic credential
- **WHEN** the user next runs `claude-docker ~/repo` without `--gateway`
- **THEN** `/root/.claude/.credentials.json` inside the container contains the persisted token
