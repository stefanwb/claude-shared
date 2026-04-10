---
name: spec
description: Spec-Driven Development (SDD) methodology — OpenSpec format, three-way binding, behavioral testing, and backfilling. Load when onboarding a project, starting new features, writing/reviewing specs, or setting up test-spec traceability.
argument-hint: [onboard|backfill|review]
---

# Spec-Driven Development (SDD)

## Core Rule

Specs are the single source of truth. All code, tests, and agent work must trace back to a spec. Tests without a spec are orphaned. Specs without tests are unvalidated.

New capabilities require a spec before merge. Existing code gets specs as you touch it. Spikes are fine — they just can't merge without a spec.

## Three-Way Binding

- Every behavior has a spec
- Every spec has tests
- Every test traces to a spec
- If any one drifts, the other two catch it

## OpenSpec Format

`{spec-root}/specs/<capability>/spec.md` (default `spec-root`: `openspec/`, configurable per project in `CLAUDE.md`):

- `## Purpose` — what the capability manages
- `## Requirements` — `### Requirement: <name>` with "The system SHALL..." statements
- `#### Scenario:` with GIVEN/WHEN/THEN acceptance criteria (deterministic requirements)
- `#### Boundary:` with true positive/negative examples and thresholds (replaces `#### Scenario:` for probabilistic requirements)
- `#### Known tradeoff:` documents accepted false negatives/positives and why
- Specs describe intent, not implementation. No tool names, service names, or implementation details.

## Testing

**Deterministic behaviors** (fixed input → fixed output): direct GIVEN/WHEN/THEN scenarios.

**Probabilistic behaviors** (heuristics, context, thresholds): boundary tests:
- Input + context that must cross a threshold (true positives)
- Input + context that must stay below (true negatives)
- Edge cases with documented tradeoffs in the spec

Validation tests live in `{spec-root}/tests/<capability>/` and reference their spec: `"SPEC <capability>/<requirement>: <message>"`

See `examples/` for a complete spec with matching tests.

## Enforcement

CI runs the validation tests. A coverage check verifies every spec requirement has at least one test referencing `SPEC <capability>/<requirement>`.

## Workflow

1. **Spec** — capture intent in OpenSpec format
2. **Test** — write validation tests that map to spec scenarios
3. **Implement** — code fulfills the spec; spec is source of truth, code is disposable
4. **Validate** — run tests to verify spec compliance

Existing project without specs? Either direction works — formalize existing tests into specs, or write specs for existing behavior. The goal is convergence.
