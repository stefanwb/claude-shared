#!/usr/bin/env bash
# limit-agent-spawns.sh — Claude Code PreToolUse hook.
#
# Caps the number of subagents Claude may spawn per session (default 2) and
# requires explicit approval before any Workflow run (a single Workflow can
# spawn a dozen agents). Denies past the cap with a reason that tells Claude to
# stop and ask. A hook "ask" decision is silently downgraded to "allow" in auto
# and bypassPermissions modes, so "deny" is the only decision that holds there.
#
# Wire it up in settings.json with matcher "Agent|Workflow" (see README).
# Requires: bash, jq. Uses flock (util-linux) when present; falls back to a
# mkdir spin lock on hosts without it (macOS).
#
# Override the cap globally:      CLAUDE_AGENT_SPAWN_LIMIT=4
# Raise the cap for one session:  echo 4 > <state-dir>/agent-spawns.allow
#   The denial message prints the exact path. Run it via `! echo ...` in the
#   prompt, or let Claude run it only after you approved in the conversation.
set -euo pipefail

limit="${CLAUDE_AGENT_SPAWN_LIMIT:-2}"
input="$(cat)"

tool="$(jq -r '.tool_name // empty' <<<"$input")"
session="$(jq -r '.session_id // "unknown"' <<<"$input")"
state_dir="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
[ -n "$state_dir" ] || state_dir="${TMPDIR:-/tmp}/claude-agent-cap/${session}"
mkdir -p "$state_dir"

count_file="$state_dir/agent-spawns.count"
allow_file="$state_dir/agent-spawns.allow"
lock_path="$state_dir/agent-spawns.lock"

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Read the first line of a file into a variable (empty if the file is missing).
read_file() { # var file
  local -n out="$1"
  out=""
  [ -f "$2" ] || return 0
  read -r out < "$2" || true
}

# Parallel Agent calls fire this hook concurrently; serialise the counter update.
# flock is released automatically when the process exits. Note: `mkdir` is not
# atomic on Docker overlay filesystems, so the mkdir fallback is only for hosts
# without flock.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$lock_path"
  flock -w 5 9 || true
else
  for _ in $(seq 1 50); do
    if mkdir "$lock_path" 2>/dev/null; then break; fi
    sleep 0.1
  done
  trap 'rmdir "$lock_path" 2>/dev/null || true' EXIT
fi

read_file count "$count_file"
: "${count:=0}"
read_file cap "$allow_file"
: "${cap:=$limit}"

approve_hint="If the user approves in this conversation, raise the session cap with: echo <new-cap> > $allow_file — then retry. Do not run that command without the user's approval."

case "$tool" in
  Workflow)
    # A Workflow is a multi-agent fan-out; it is never covered by the default cap.
    if [ ! -f "$allow_file" ]; then
      deny "Workflow runs spawn many agents and need the user's explicit approval first. Stop and ask. $approve_hint"
    fi
    ;;
  Agent)
    next=$((count + 1))
    if [ "$next" -gt "$cap" ]; then
      deny "Agent spawn limit reached: $count of $cap subagents already spawned this session. Stop and ask the user for explicit approval before spawning more. $approve_hint"
    fi
    printf '%s\n' "$next" > "$count_file"
    ;;
esac

# No decision printed: fall through to the normal permission flow.
exit 0
