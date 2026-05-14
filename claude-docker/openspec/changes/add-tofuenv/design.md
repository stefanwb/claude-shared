## Context

claude-docker today bundles `tfenv` plus the `--tfe` credential opt-in for
Terraform Cloud (`app.terraform.io`). OpenTofu has matured into a peer
ecosystem with its own version-pinning convention (`.opentofu-version`),
its own CLI config file (`~/.tofurc`), and a binary distribution channel
on `github.com/opentofu/opentofu/releases` — but the credential surface
(`~/.terraform.d/credentials.tfrc.json`, `TF_TOKEN_<host>` env vars) is
*shared* with Terraform for back-compat. OpenTofu workflows are blocked
inside the container in the same two ways `--tfe` historically was:

1. No path to a project-pinned `tofu` binary; the image ships none and no
   version manager covers it.
2. No way to expose tofu-specific host CLI configuration (`~/.tofurc` —
   plugin caches, dev_overrides, provider installation overrides) without
   pasting files in by hand.

`tofuenv` is the OpenTofu-side analogue of `tfenv` from the same `tofuutils`
community: pure bash, MIT, identical UX (`tofuenv install` reads
`.opentofu-version`). The decision to add `--tofu` as a sibling flag to
`--tfe` (rather than overloading `--tfe`) keeps the opt-in semantics
explicit: the user is asking for OpenTofu access, not Terraform Cloud.

## Goals / Non-Goals

**Goals:**

- A `tofu` binary on demand inside the container, version-pinned by the
  project (`.opentofu-version`), with no baked-in version policy from the
  image.
- Tofu-specific CLI config (`~/.tofurc`) exposed read-only inside the
  container, gated on an explicit `--tofu` opt-in, matching the existing
  credential-flag pattern.
- Authenticated `app.terraform.io` access for `tofu` (the shared HCP
  Terraform credential file) via the same flag, with the credential leak
  guard widened to cover an in-container `tofu login`.
- No regression in the default (no-flag) security posture: a user who does
  not pass `--tofu` (and did not pass `--tfe`) must not inherit any TFC
  credentials from a prior session.
- Threat model stays explicit: the new runtime code-fetch primitive
  (`tofuenv install`) is documented in the same class as `pnpm dlx`,
  `uvx`, `tfenv install`.

**Non-Goals:**

- Replacing `tfenv` with `tenv` (the unified terraform+opentofu+terragrunt
  manager). Out of scope; potential follow-up if the dual install proves
  awkward in practice.
- Self-hosted Terraform Enterprise hostnames or non-TFC `TF_TOKEN_<host>`
  expansion. Same scope decision as `--tfe`.
- `~/.tofurc` *write* persistence. The mount is read-only; in-container
  edits do not propagate to the host.
- A separate `tofu login` credential file path. OpenTofu writes to
  `~/.terraform.d/credentials.tfrc.json` (the same shared file Terraform
  uses) and that path is already in scope here.
- OpenTofu provider mirror bundling. Mirrors are configured via
  `~/.tofurc`, which the mount surfaces; the image stays neutral.

## Decisions

### D1: Add `tofuenv`, not a `tofu` binary

OpenTofu versions are project-pinned via `.opentofu-version` and
`required_version` constraints. A single bundled tofu version drifts
against real workspaces the moment any project upgrades or downgrades.
`tofuenv` reads `.opentofu-version` and fetches the pinned binary on
demand, keeping the image neutral on version policy. Identical reasoning
to D4 of `add-tfe-support` for `tfenv`.

**Alternatives considered:**
- *Bundle the latest tofu.* Rejected — guaranteed to mismatch the moment
  a workspace pins an older version; OpenTofu's release cadence is fast
  enough that "latest" is a moving target.
- *Bundle several pinned versions.* Rejected — combinatorial; image
  bloat; no version set satisfies every consumer.
- *`tenv` (unified manager).* Rejected for this change — would replace
  the existing `tfenv` install, which is a behaviour change for `--tfe`
  users. Worth its own proposal if dual-tool maintenance proves painful.

### D2: New `--tofu` flag, not overloaded `--tfe`

`--tfe` reads as "Terraform Cloud" (the flag was named when only
Terraform CLI existed). Mounting `~/.tofurc` under `--tfe` would be
surprising — the flag name does not signal OpenTofu intent. A sibling
`--tofu` flag preserves the explicit-consent model: the user states
which ecosystem they're enabling.

The two flags compose freely: `claude-docker --tfe --tofu ~/repo` enables
both with no special-case logic; the shared cred-file mount is
idempotent (`-v src:dst:ro` on the same path is fine), the env-var
forwarding is set-union, and the tmpfs mask is correctly suppressed.

**Alternatives considered:**
- *Single `--iac` (or `--terraform`) flag.* Rejected — collapses intent
  and forces tofu-specific behaviour (`~/.tofurc` mount) onto Terraform
  users who don't want it.
- *Auto-detect from `.opentofu-version`.* Rejected — credential mounting
  cannot be inferred from workspace contents without violating
  default-deny.

### D3: Mount `~/.tofurc` (file), not `~/.opentofu/` (dir)

OpenTofu's per-user CLI config lives at `~/.tofurc`. The directory
`~/.opentofu/` exists on some installs but holds cache and runtime state
the container should not inherit. The `~/.terraform.d/` directory is the
authoritative *credentials* location (shared with Terraform) — surfacing
that via the existing TFC mount is sufficient.

Mounting a single file (not a directory) means the leak-guard tmpfs trick
(`--tmpfs /root/.tofurc`) does not apply cleanly: tmpfs mounts on a
single-file path is awkward and would mask other files. This is
acceptable here because `~/.tofurc` is not a credential — it is CLI
configuration (provider mirror overrides, plugin cache dir,
`dev_overrides` blocks). A prior `--tofu` session's `~/.tofurc` writes
(if any) persist to `claude-code-root` and remain readable to a later
no-flag session. Documented in the threat model as residual config
leakage, not a credential leak.

**Alternatives considered:**
- *Mount `~/.opentofu/` as a dir.* Rejected — `~/.tofurc` is the
  documented CLI config path; the directory is implementation detail.
- *Tmpfs-mask `/root/.tofurc` when `--tofu` not set.* Rejected as
  unnecessary for a non-credential file; the docker run line is
  already long and a `--mount type=tmpfs,destination=/root/.tofurc`
  would block read-only legitimate use of the path.

### D4: Widen the `/root/.terraform.d/` tmpfs mask to gate on `--tfe || --tofu`

Today the mask is applied when `WITH_TFE=0` and `EPHEMERAL=0`. Without
widening, a user who passes `--tofu` (and runs `tofu login`
app.terraform.io) would leave a token at
`/root/.terraform.d/credentials.tfrc.json` that a subsequent
no-flag-no-`--tfe` session would silently inherit — the exact leak the
existing mask was designed to prevent for Terraform.

The widened condition is `WITH_TFE=0 && WITH_TOFU=0 && EPHEMERAL=0`. No
existing user is affected: a user who never passes `--tofu` still hits
the mask whenever `--tfe` is unset, identical to today's behaviour.

### D5: Pin `tofuenv` itself; do *not* pin the tofu binaries it fetches

`tofuenv` is a build-time dependency and follows the same "version
pinned + sha256-verified" rule as `tfenv`, `gh`, `glab`, the AWS CLI, and
`uv`.

The tofu binaries `tofuenv install` downloads at runtime are deliberately
*not* pinned by the image. They are version-selected by the user's
project (`.opentofu-version`), and pinning them in the image would defeat
the entire reason `tofuenv` is here. This is the same carve-out from the
"everything pinned" rule that `tfenv` already has, and it must be
documented in the threat model.

### D6: Document `tofuenv install` in the existing runtime-fetch class

`npx`, `pnpm dlx`, `uvx`, and `tfenv install` are already documented as
primitives that fetch and execute arbitrary code at runtime. `tofuenv
install` is the same class — pulls a signed binary from
`github.com/opentofu/opentofu/releases` and runs it — and the
documentation needs to say so explicitly so users are not surprised by a
fourth runtime network-egress vector.

The trust anchor is `github.com/opentofu/opentofu/releases` over TLS via
the system CA bundle. The OpenTofu release artifacts ship with
`SHA256SUMS` files; `tofuenv` verifies the SHA but does *not* verify the
GPG/cosign signature by default. Documented as-is; not in scope to
re-implement signature verification on top.

### D7: Install location `/opt/tofuenv` (mirror tfenv)

`/opt` is chosen for the same reason `tfenv` lives there: the
`claude-code-root` named volume masks `/root` at runtime, so anything
baked under `/root` in the image gets frozen by the volume the first time
a user runs the image and future image-level upgrades to tofuenv itself
would not propagate. `/opt` is part of the writable layer instead — image
upgrades take effect on next run.

Trade-off (same as tfenv): `tofuenv install` caches tofu binaries under
`/opt/tofuenv/versions/`, which is *not* covered by the `claude-code-root`
volume, so installed tofu versions are discarded on `docker run --rm`
exit. Every session re-downloads. Documented in README; power users can
build a child image that runs `tofuenv install <version>` at build time
to bake a specific version into a derived image.

## Risks / Trade-offs

- **Risk:** Two version managers (`tfenv` + `tofuenv`) in the image is
  redundant when `tenv` could subsume both.
  → **Mitigation:** Acknowledged; called out as non-goal D1-alt. Both
  tools are tiny (pure bash, ~25KB each); the cost of running them
  side-by-side is negligible. A future `tenv` migration is additive to
  decide later, not a blocker here.

- **Risk:** The widened tmpfs-mask condition (`--tfe || --tofu`) changes
  behaviour for a user who *only* passes `--tofu` — previously they
  would have hit the mask (because `WITH_TFE=0`), now they will not.
  → **Mitigation:** This is intentional. The user opted in to OpenTofu
  credentials; they should see the persisted TFC creds from a prior
  `--tofu` session, exactly as the `--tfe` flag does for Terraform. No
  existing user is affected because `--tofu` does not exist today.

- **Risk:** `~/.tofurc` is mounted without a leak guard.
  → **Mitigation:** `~/.tofurc` is CLI configuration, not credentials.
  Persistence via `claude-code-root` of a tofu-specific config block
  (e.g. a custom plugin cache path) is not a credential leak. Documented
  as residual config in the threat model. A tofu-specific
  `~/.tofurc.local` mask via tmpfs file-mount is feasible if it becomes
  a real concern later.

- **Risk:** Runtime-fetched `tofu` binary is arbitrary code with no
  build-time SHA pin in this image.
  → **Mitigation:** Documented in threat model alongside `tfenv install`,
  `pnpm dlx`, `uvx`. Trust anchor is
  `github.com/opentofu/opentofu/releases` + TLS + the project's release
  signing. Users who need stricter posture can pre-stage a vetted tofu
  binary on the host and PATH-mount it; not built in.

- **Trade-off:** Combined `--tfe --tofu` produces overlapping mounts for
  `~/.terraform.d/credentials.tfrc.json`. `docker run -v src:dst:ro -v
  src:dst:ro` is idempotent in current Docker engines but the second
  `-v` is technically a no-op the daemon evaluates.
  → **Mitigation:** Behaviour verified in smoke tests. The duplicate mount
  is harmless and the alternative (collapse-into-one block) couples the
  two flags' implementations more than is worth.

## Migration Plan

Purely additive. No existing flag behaviour changes. No image entrypoint
changes. Rollback is removing the `--tofu` branch from `run.sh`, the
`tofuenv` install block from the Dockerfile, and reverting the
tmpfs-mask condition to its single-`WITH_TFE` form — all three are
localized and side-effect free outside their own opt-in path.

## Open Questions

- Should `--tofu` and `--tfe` ever be consolidated under a single
  `--iac` flag once both ecosystems are first-class? Current answer: no
  — explicit ecosystem opt-in matches `--gh`/`--glab` separation and
  reads better than a generic name.
- Should `tofuenv install` use the optional `cosign` signature verification
  upstream now supports? Current answer: out of scope; the SHA-only
  trust model matches the `tfenv install` carve-out and consistency wins.
- Should the image preinstall a "blessed" tofu version (e.g. latest LTS)
  at build time so first-use is faster? Current answer: no — exact same
  trade-off as `tfenv`; build a child image if you want a baked-in
  version (`FROM claude-code:local`).
