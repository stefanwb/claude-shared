## Why

OpenTofu has become a first-class peer to Terraform — the IaC ecosystem now
routinely targets both, and several active projects (`tofu plan/apply` on HCP
Terraform, internal modules pinned via `.opentofu-version`) need a `tofu`
binary inside the container. Today the image ships `tfenv` for Terraform but
no equivalent path to OpenTofu: users either hand-install `tofu` per session
(slow, defeats the pinned-supply-chain posture of the rest of the image) or
shell out to the host.

Baking a pinned `tofu` binary into the image is rejected for the same reason
`terraform` is not bundled: OpenTofu versions are project-pinned
(`.opentofu-version`, `required_version`) and any single shipped version
drifts against real workspaces. We need a tofu version manager mirroring
`tfenv`, plus a credential opt-in that matches the existing `--tfe` shape so
the security model stays consistent.

## What Changes

- **Install `tofuenv`** in the image so users can fetch a project-pinned
  `tofu` binary on demand (`tofuenv install`, auto-detects
  `.opentofu-version`). Same install pattern as `tfenv`: pinned version,
  sha256-verified source archive, installed to `/opt/tofuenv` and symlinked
  onto `/usr/local/bin`. The image SHALL NOT ship any pre-installed `tofu`
  binary — version selection is the project's responsibility, not the
  image's.
- **Add `--tofu` opt-in flag** to `run.sh` that:
  - Mounts the host's `~/.tofurc` (the OpenTofu CLI config file, distinct
    from `~/.terraformrc`) read-only at `/root/.tofurc` when present.
  - Mounts `~/.terraform.d/credentials.tfrc.json` read-only — the same
    credentials file `tofu login` writes (OpenTofu reuses the path for
    Terraform back-compat). When combined with `--tfe`, the duplicate mount
    is idempotent (`-v src:dst:ro` on the same path).
  - Forwards `TF_TOKEN_app_terraform_io` from the host environment.
- **Extend the `/root/.terraform.d/` tmpfs mask** so it is applied only
  when *both* `--tofu` and `--tfe` are unset. Today the mask is gated on
  `--tfe` alone; widening it keeps the same leak guarantee for an
  in-container `tofu login`.
- **Update the threat model** to note `tofuenv install` as a fourth
  runtime code-fetch primitive (alongside `npx`, `pnpm dlx`, `uvx`,
  `tfenv install`), pulling from `github.com/opentofu/opentofu/releases`.
- **Document the runtime-fetch risk** in the same class as the existing
  primitives: tofuenv verifies sha256 of release artifacts via its own
  shipped `SHA256SUMS` but the image does not GPG-verify the upstream
  signing key.
- **Update README** "Bundled CLIs" line, Credential opt-in table, Auth
  model, and Terraform Cloud workflow section to cover the new flag and
  tool.

Out of scope (deliberately):
- Replacing `tfenv` with the unified `tenv` (terraform + opentofu +
  terragrunt + atmos). That is a non-additive change with a wider review
  surface; if it lands, it lands separately.
- Per-host TF_TOKEN_<host> forwarding beyond `app.terraform.io`.
- A `~/.tofurc` *write* path. The mount is read-only; in-container config
  changes do not persist to the host.
- OpenTofu provider registry overrides specific to private mirrors. Those
  are configured *via* `~/.tofurc` so the mount surface is sufficient; the
  image itself stays neutral on registry policy.

## Capabilities

### New Capabilities

None. This change extends existing capabilities rather than introducing a
new one.

### Modified Capabilities

- `external-cli-tools`: adds the `--tofu` opt-in flag (mounts `~/.tofurc`
  and the shared TFC credentials file, forwards
  `TF_TOKEN_app_terraform_io`, extends the `/root/.terraform.d/` tmpfs mask
  to gate on both `--tfe` and `--tofu`) and adds `tofuenv` (and the `tofu`
  shim) to the set of bundled binaries on the default PATH. The "version
  pinned and sha256-verified" requirement applies to `tofuenv` itself; the
  `tofu` binaries it fetches at runtime are intentionally not pinned by
  this image.
- `package-managers`: the threat-model documentation requirement is
  extended to cover `tofuenv install` as a fourth runtime code-fetch
  primitive (alongside `pnpm dlx`, `uvx`, `tfenv install`).

## Impact

- **Code**: `claude-docker/Dockerfile` (install `tofuenv`, pin its version
  + sha256), `claude-docker/run.sh` (parse `--tofu`, mount `~/.tofurc`,
  widen the TFC mount/env/mask logic to OR-gate on `WITH_TFE` ||
  `WITH_TOFU`).
- **Docs**: `claude-docker/README.md` (bundled CLIs list, opt-in table,
  Auth model, Terraform Cloud workflow, threat-model bullet).
- **Specs**: deltas to `external-cli-tools` and `package-managers`.
- **No breaking changes**: existing flags and defaults unchanged; `--tofu`
  is purely additive, and the tmpfs-mask widening keeps the same behaviour
  for users who never pass `--tofu` (still gated on `--tfe` alone in their
  case).
- **Dependencies**: adds `tofuenv` (pure-bash, MIT-licensed, ~72KB source
  archive). Adds runtime network egress to
  `github.com/opentofu/opentofu/releases` *only when* the user invokes
  `tofuenv install` inside the container.
