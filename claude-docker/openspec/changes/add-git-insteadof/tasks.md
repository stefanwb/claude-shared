## 1. Container entrypoint

- [ ] 1.1 Create `claude-docker/entrypoint.sh` — POSIX `sh`, no bashisms; reads `GH_TOKEN` / `GITHUB_TOKEN` and `GITLAB_TOKEN`, plus `CLAUDE_DOCKER_GITHUB_HOSTS` / `CLAUDE_DOCKER_GITLAB_HOSTS` (defaults: `github.com` / `gitlab.com`); writes `git config --system url."https://oauth2:$TOKEN@$HOST.insteadOf" "https://$HOST"` for each authenticated host; then `exec "$@"`
- [ ] 1.2 Add `set -eu` to the entrypoint; guard each token block with `[ -n "$TOK" ]` so missing-token paths are no-ops, not errors; ensure non-zero exit only when `exec "$@"` itself fails

## 2. Dockerfile

- [ ] 2.1 `COPY entrypoint.sh /usr/local/bin/claude-docker-entrypoint` and `RUN chmod +x /usr/local/bin/claude-docker-entrypoint`, placed AFTER the tmux conf RUN block (so edits to the entrypoint script don't invalidate heavier upstream layers)
- [ ] 2.2 Add `ENTRYPOINT ["/usr/local/bin/claude-docker-entrypoint"]` (keep `CMD ["claude"]` unchanged so `docker run image` semantics for non-claude-docker users remain identical)

## 3. run.sh

- [ ] 3.1 Add a `glab auth token` host fallback mirroring the existing `gh auth token` fallback (run.sh:201-210): if `--glab` is set and `GITLAB_TOKEN` is unset on the host, try `glab auth token`, export it, append `-e GITLAB_TOKEN` to `ENV_ARGS`; silent on failure
- [ ] 3.2 Add a `_extract_hosts_from_gh()` helper that reads `~/.config/gh/hosts.yml` and prints comma-separated top-level keys (these are hostnames); silent and empty-output on missing/unparseable file
- [ ] 3.3 Add a `_extract_hosts_from_glab()` helper that reads `~/.config/glab-cli/config.yml` and prints comma-separated keys under the `hosts:` section; silent and empty-output on missing/unparseable file
- [ ] 3.4 When `--gh` is set, run the helper and (if non-empty) append `-e CLAUDE_DOCKER_GITHUB_HOSTS=<csv>` to `ENV_ARGS`; entrypoint will default to `github.com` when the env is absent
- [ ] 3.5 Same shape for `--glab` and `CLAUDE_DOCKER_GITLAB_HOSTS`

## 4. Smoke tests

- [ ] 4.1 `docker build -t claude-code:local ./claude-docker` succeeds; image inspect shows the ENTRYPOINT set correctly
- [ ] 4.2 No-flag invariant unchanged: `docker run --rm claude-code:local sh -c 'git config --system --list | grep insteadOf || echo none'` prints `none` (no rewrites injected when no tokens forwarded)
- [ ] 4.3 `--gh` with explicit token: `docker run --rm -e GH_TOKEN=ghp_fake -e CLAUDE_DOCKER_GITHUB_HOSTS=github.com claude-code:local sh -c 'git config --system --get-all url.https://oauth2:ghp_fake@github.com.insteadOf'` prints `https://github.com`
- [ ] 4.4 `--glab` with explicit token + custom host: `docker run --rm -e GITLAB_TOKEN=glpat_fake -e CLAUDE_DOCKER_GITLAB_HOSTS=gitlab.com,sbp.gitlab.schubergphilis.com claude-code:local sh -c 'git config --system --list | grep insteadOf'` shows both rewrites
- [ ] 4.5 Default-host behaviour: `docker run --rm -e GITLAB_TOKEN=glpat_fake claude-code:local sh -c 'git config --system --get-all url.https://oauth2:glpat_fake@gitlab.com.insteadOf'` prints `https://gitlab.com` (default kicks in when CLAUDE_DOCKER_GITLAB_HOSTS unset)
- [ ] 4.6 No-leak verification: a previous container with `--gh` and a real token leaves NO trace inside a follow-up `docker run --rm claude-code:local sh -c 'cat /etc/gitconfig'` — the writable layer is discarded on `--rm`
- [ ] 4.7 User-config override: with `--gh` set AND `/root/.gitconfig` from `claude-code-root` containing a custom `url.<github.com>.insteadOf`, `git config --get-all url.https://github.com.insteadOf` reports the user config (--global wins over --system)
- [ ] 4.8 End-to-end with a real private repo: `claude-docker --gh ~/some-private-gh-repo`, then inside the container `git ls-remote https://github.com/<priv>/<repo>` succeeds without prompting for a username
- [ ] 4.9 End-to-end with `--glab` against SBP GitLab: `tofu init` in a workspace with a private SBP GitLab module source completes without `could not read Username` error

## 5. Documentation

- [ ] 5.1 Extend the `--gh` row in the Auth model table: note that the forwarded GH_TOKEN is also used to populate a system-level `git config insteadOf` rewrite for each authenticated GitHub host enumerated from `~/.config/gh/hosts.yml`
- [ ] 5.2 Extend the `--glab` row in the Auth model table: same shape, plus mention of the new `glab auth token` host fallback
- [ ] 5.3 Add a "Private git module fetch" subsection covering the standard usage flow (`claude-docker --glab ~/repo` → `tofu init` works); scope (HTTPS only, not SSH); ephemerality (token lives in `/etc/gitconfig`, discarded on container exit); user override (`~/.gitconfig` --global wins)
- [ ] 5.4 Update the Threat model section's "Exposed" bullet to mention that `--gh`/`--glab` now make their respective tokens visible to in-container `git` via a system-level config rewrite — same blast radius as the already-forwarded env var, just a different surface

## 6. Validation

- [ ] 6.1 `openspec validate add-git-insteadof --strict` exits 0
- [ ] 6.2 `claude-docker --help` round-trips unchanged (no new flags added — the feature is additive to existing flags' behaviour)
- [ ] 6.3 Spot-check that `--ephemeral` still works: with `--gh --ephemeral`, the insteadOf injection happens (entrypoint runs regardless), and the persisted-host-config rule (`/root/.config/gh/` tmpfs mask) is unaffected — the entrypoint touches `/etc/`, not `/root/`
