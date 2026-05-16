#!/bin/sh
# claude-docker-entrypoint: translate forwarded credential tokens into
# system-level git insteadOf rewrites so in-container `git` can clone
# private HTTPS repos against the same hosts the matching CLI tool
# (`gh` / `glab`) was opted in for. See openspec/changes/add-git-insteadof/.
#
# Writes /etc/gitconfig (--system), NOT /root/.gitconfig (--global), so
# the rewrite (and the token inside it) is gone with the writable layer
# on `docker run --rm` exit — never persists via the claude-code-root
# named volume. Precedence: --local > --global > --system, so a user's
# own /root/.gitconfig entry wins, preserving user intent.
set -eu

# Inject `url.<host>.insteadOf` rewrites for each host in a CSV list.
# No-op on empty token or empty host list — that path is the
# no-opt-in case where this script should be invisible.
inject_insteadof() {
  tok=$1
  hosts=$2
  [ -n "$tok" ] || return 0
  [ -n "$hosts" ] || return 0
  # POSIX field-splitting on comma; for-loop avoids the
  # `while read` pipeline subshell whose set -e semantics differ
  # across dash/bash. Save/restore IFS so we don't perturb callers.
  old_ifs=$IFS
  IFS=','
  for host in $hosts; do
    [ -n "$host" ] || continue
    git config --system "url.https://oauth2:${tok}@${host}.insteadOf" "https://${host}"
  done
  IFS=$old_ifs
}

# GH_TOKEN takes precedence over GITHUB_TOKEN (matches gh's own
# precedence rule). Default host is github.com when
# CLAUDE_DOCKER_GITHUB_HOSTS is absent — covers the public-only case
# when host enumeration found nothing.
gh_tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
inject_insteadof "$gh_tok" "${CLAUDE_DOCKER_GITHUB_HOSTS:-github.com}"

# GITLAB_TOKEN is the env var glab and the GitLab API both honour;
# no GITHUB_TOKEN-style synonym to pick between.
inject_insteadof "${GITLAB_TOKEN:-}" "${CLAUDE_DOCKER_GITLAB_HOSTS:-gitlab.com}"

# `exec` so signals (Ctrl-C in tmux, container stop) reach claude/tmux
# directly without an extra shell hop intercepting them.
exec "$@"
