## 1. Image: install tofuenv

- [ ] 1.1 Pick a pinned `TOFUENV_VERSION` (latest stable tofuenv tag from `github.com/tofuutils/tofuenv`) and compute the sha256 of its release source archive; record both as Dockerfile `ARG`s alongside the existing `TFENV_*` ARGs (single hash is fine — tofuenv is a pure bash script archive, arch-independent)
- [ ] 1.2 Add a Dockerfile `RUN` block immediately after the existing `tfenv` block that downloads the pinned tofuenv archive, runs `sha256sum -c` against `TOFUENV_SHA256`, extracts to `/opt/tofuenv`, and symlinks `/opt/tofuenv/bin/tofuenv` (and the `tofu` shim) onto `/usr/local/bin/`
- [ ] 1.3 Verify the build: `docker build -t claude-code:local ./claude-docker` succeeds on the local arch and `docker run --rm claude-code:local tofuenv --version` prints a version; `docker run --rm claude-code:local tofu version` before any install exits non-zero (dispatcher reports no version installed)
- [ ] 1.4 Verify negative path: temporarily flip one byte of `TOFUENV_SHA256`, rerun `docker build`, confirm the build fails at `sha256sum -c` before tofuenv is installed; revert the change

## 2. Wrapper: --tofu flag

- [ ] 2.1 In `run.sh`, add `WITH_TOFU=0` alongside the other `WITH_*` initializers and a `--tofu) WITH_TOFU=1 ;;` arm in the case statement
- [ ] 2.2 Under `--tofu`, append `-v "$HOME/.tofurc:/root/.tofurc:ro"` to `MOUNT_ARGS` only when the host file exists (silent no-op otherwise, mirroring `--gh`'s silent fallback); follow the same `[ -f ... ]` guard pattern used for `~/.aws/config`
- [ ] 2.3 Widen the existing TFC credentials-file mount guard to fire on `WITH_TFE=1` OR `WITH_TOFU=1` (the file is shared between Terraform and OpenTofu; `tofu login` writes to the same path)
- [ ] 2.4 Widen the existing `ENV_VARS+=(TF_TOKEN_app_terraform_io)` line to fire on `WITH_TFE=1` OR `WITH_TOFU=1`
- [ ] 2.5 Widen the existing `/root/.terraform.d` tmpfs mask gate (`[ "$WITH_TFE" = "0" ]`) to require both `WITH_TFE=0` AND `WITH_TOFU=0`, with a one-line comment noting the leak guard covers `terraform login` and `tofu login` equally
- [ ] 2.6 Append `tofu` to `DOCKER_FLAGS` when `WITH_TOFU=1` so the statusline tag reflects the opt-in (insert next to the existing `tfe` line so emitted order stays predictable)
- [ ] 2.7 Update the `print_help` heredoc with a `--tofu` row matching the `--tfe` style (one-line summary: mounts `~/.tofurc` read-only, also mounts the shared `~/.terraform.d/credentials.tfrc.json` and forwards `TF_TOKEN_app_terraform_io`; targets OpenTofu against `app.terraform.io`)

## 3. Smoke tests against scenarios

- [ ] 3.1 No-flag invariants: `claude-docker ~/repo` (no flags) → inside the container, `/root/.tofurc` does not exist; `/root/.terraform.d/` is empty; `echo $TF_TOKEN_app_terraform_io` is empty — even after a prior `--tofu` session that ran `tofu login`
- [ ] 3.2 `--tofu` file mount: with a host `~/.tofurc` present, `claude-docker --tofu ~/repo` exposes the file read-only inside the container; an in-container `: > /root/.tofurc` fails with EROFS
- [ ] 3.3 `--tofu` shared cred-file mount: with a host `~/.terraform.d/credentials.tfrc.json` present, `claude-docker --tofu ~/repo` exposes the file read-only inside the container (same path the `--tfe` flag exposes)
- [ ] 3.4 `--tofu` env-var forwarding: with `TF_TOKEN_app_terraform_io=<token>` exported on the host, `claude-docker --tofu ~/repo` forwards it; without `--tofu` (and without `--tfe`), it does not
- [ ] 3.5 `--tofu` silent absence: with no host `~/.tofurc`, no `~/.terraform.d/credentials.tfrc.json`, and no env var set, `claude-docker --tofu ~/repo` starts cleanly (no error printed) and `/root/.tofurc` does not exist inside the container
- [ ] 3.6 Persistence-leak guard: run `claude-docker --tofu ~/repo`, simulate `tofu login app.terraform.io` (write to `/root/.terraform.d/credentials.tfrc.json` in the `claude-code-root` named volume), exit, then run `claude-docker ~/repo` (no flag) — confirm `/root/.terraform.d/` is empty inside the second session
- [ ] 3.7 `tofuenv install` end-to-end: in a workspace containing `.opentofu-version` with `1.8.0`, `tofuenv install` downloads from `github.com/opentofu/opentofu/releases` and installs; `tofu version` reports `1.8.0`
- [ ] 3.8 Statusline tag includes `tofu`: launch `claude-docker --tofu --gh ~/repo` and confirm the statusline prefix shows `docker:gh,tofu` (or whatever order the existing builder emits)
- [ ] 3.9 `--tfe --tofu` composes: `claude-docker --tfe --tofu ~/repo` mounts both `~/.tofurc` and `~/.terraform.d/credentials.tfrc.json` (the latter unaffected by the duplicate `-v`); statusline tag includes both `tfe,tofu`

## 4. Documentation

- [ ] 4.1 Update the "Bundled CLIs on the default PATH" line at the top of `README.md` to include `tofuenv` (the `tofu` shim is available via tofuenv just like the `terraform` shim is via tfenv — mention it the same way)
- [ ] 4.2 Add a `--tofu` row to the **Credential opt-in** table in `README.md`, matching the `--tfe` voice (mention: `~/.tofurc` file mount, shared TFC cred-file mount + env-var forwarding, residual `~/.tofurc` config not masked, persistence-mask widening for `~/.terraform.d/`)
- [ ] 4.3 Extend the **Auth model** section with a `--tofu` row covering source of credentials and the widened persistence-mask rule
- [ ] 4.4 Update the **Threat model** "Runtime code-fetch" bullet to add `tofuenv install` as a fourth primitive (note: pulls from `github.com/opentofu/opentofu/releases`, tofu binary is *not* sha256-pinned in the image because the project picks the version)
- [ ] 4.5 Extend the **Terraform Cloud workflow** section (renamed or sub-sectioned for OpenTofu) to document the standard usage flow: `tofu login app.terraform.io` once on the host → `claude-docker --tofu ~/repo` → `tofuenv install` to materialize a project-pinned tofu → `tofu plan`

## 5. Validation

- [ ] 5.1 `openspec validate add-tofuenv --strict` exits 0
- [ ] 5.2 `claude-docker --help` output round-trips: every wrapper flag listed in the help text has a matching arm in the case statement and vice versa (including the new `--tofu`)
- [ ] 5.3 Spot-check that `--ephemeral` still works alongside `--tofu`: `claude-docker --ephemeral --tofu ~/repo` mounts `~/.tofurc` and the shared cred file and forwards the env var but skips the named volumes (so the tmpfs mask block is bypassed cleanly)
