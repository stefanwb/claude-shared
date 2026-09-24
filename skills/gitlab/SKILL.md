---
name: gitlab
description: Reference for the `glab` CLI tool — MR creation/editing, CI status/trace/retry, and VPN diagnostics for GitLab. MUST be loaded before running any `glab` command. Use when working with GitLab merge requests, pipelines, or connectivity issues.
argument-hint: [mr|ci|vpn]
---

# GitLab `glab` CLI Reference

Use this reference when performing GitLab operations. Always use `glab` — never `lab` or `gh` for GitLab.

Docs: https://docs.gitlab.com/cli/

## `glab mr create`

Syntax: `glab mr create [flags]`

| Flag | Purpose |
|------|---------|
| `-t "Title"` | MR title |
| `-d "Description"` | MR description (use `-d "$(cat file.md)"` for file input) |
| `--squash-before-merge` | Squash on merge |
| `--remove-source-branch` | Delete source branch after merge |
| `--draft` | Create as draft MR |
| `--reviewer username` | Assign reviewer |
| `-a username` | Assign assignee |
| `-l label` | Add label |
| `-m "milestone"` | Set milestone (**note:** `-m` is milestone, NOT message) |

Example:
```sh
glab mr create -t "Title" -d "Description" --squash-before-merge --remove-source-branch
```

## `glab mr update`

Syntax: `glab mr update <id> [flags]`

| Flag | Purpose |
|------|---------|
| `-t "Title"` | Update title |
| `-d "Description"` | Update description (use `-d "$(cat file.md)"` for file input) |
| `--target-branch <branch>` | Change target branch |
| `--draft` / `--ready` | Mark as draft / ready |
| `-l label` / `-u label` | Add / remove label |
| `-a username` / `-a '!username'` | Add / remove assignee |
| `--reviewer username` / `--reviewer '!username'` | Add / remove reviewer |
| `-m "milestone"` | Set milestone (use `""` to unassign) |

Examples:
```sh
glab mr update 12 -d "$(cat description.md)"
glab mr update 18 --target-branch master
glab mr update 23 -a '+johndoe' -a '!janedoe'
```

## `glab mr close`

Syntax: `glab mr close <id>`

No inline comment flag — use `glab mr note` first to leave a closing reason:

```sh
glab mr note 45 -m "Closing — superseded by direct commits on main."
glab mr close 45
```

## Keeping MRs in sync

**Before asking the user to review an MR, the title and description must describe the current diff.** This is a gate, not a nicety: do not post "ready for review", assign a reviewer, mark an MR ready, or hand it back to the user until you have re-read the diff and confirmed the title and description still match it.

This applies to every hand-off, not just the first one. The common miss is **rework**: the user reviews, you push fixes, and you hand the MR back with a title and description still describing the original attempt. Re-run the check after every round of rework, including rebases, force-pushes, scope changes, and commits that drop or add work.

Each time you are about to hand an MR back:

1. `glab mr diff <id>` — read what the branch actually does now.
2. `glab mr view <id>` — read what the MR currently claims.
3. If they disagree on scope, behaviour, or the test plan, update it before saying anything to the user.
4. Tell the user you refreshed the title/description, so they know it is current.

```sh
glab mr update <id> -t "Updated title" -d "$(cat <<'EOF'
Updated description...
EOF
)"
```

Only a push that leaves the diff's scope unchanged — a typo fix, a lint pass, a comment — needs no edit. When in doubt, update.

## Reviewing an MR

**Model and effort.** MR reviews run on Opus at **low** effort. Delegate the review to the `tech-lead` agent; its definition pins `model: opus` and `effort: low`, so it is the default path. `/code-review low` is an alternative only when the session model is already Opus, because `/code-review` runs on the session model. Always type the level: a bare `/code-review` reuses whatever level was typed last, not `low`. Do not review at the session's default (higher) effort and do not switch to another model.

**One reviewer, no fan-out.** A review is a single agent's job. Do not spawn extra agents to split a review by file, dimension, or verification pass. If a change needs a specialist pass (security, cost), name it in the review and let the user decide. This is part of the delegation policy: never more than 2 agents per session without explicit approval (see the `claude-shared` README).

### Step 1 — Read the change

```sh
glab mr view <id>                # title, description, state
glab mr view <id> -F json        # full MR object as JSON (filter with --jq)
glab mr diff <id>                # full diff
```

If the title or description no longer matches the diff, refresh it first (see *Keeping MRs in sync*) — a review against a stale description wastes the reviewer's time.

### Step 2 — Fetch the diff refs (needed for inline comments)

Fetch these immediately before posting. A push to the source branch changes `head_commit_sha` and stale refs are rejected.

```sh
glab api projects/:id/merge_requests/<id>/versions --jq '.[0] | {base_commit_sha, head_commit_sha, start_commit_sha}'
```

`:id` is resolved by `glab` to the current project, so this works from inside the repo checkout.

### Step 3 — Post the review

Post one summary note plus one inline thread per finding. Post everything in one pass; the author may start fixing the first batch before a second one lands.

```sh
# Summary note (verdict + anything that cannot be anchored to a diff line)
glab mr note <id> -m "$(cat <<'EOF'
Overall review notes.
EOF
)"

# Inline thread on a line in the diff
glab api projects/:id/merge_requests/<id>/discussions -X POST   -f body="Comment text"   -f 'position[position_type]=text'   -f 'position[base_sha]=<base_commit_sha>'   -f 'position[head_sha]=<head_commit_sha>'   -f 'position[start_sha]=<start_commit_sha>'   -f 'position[new_path]=src/foo.py'   -f 'position[old_path]=src/foo.py'   -f 'position[new_line]=42'
```

Line targeting rules:

- `new_line` is the right-side line number for added or unchanged lines. For a removed line, pass `old_line` instead and omit `new_line`.
- The line **must be inside a diff hunk** (check `glab mr diff <id>` for the `@@` headers). Findings on untouched lines go in the summary note, not an inline thread.
- `-f` sends the value as a raw string, which is what the discussions API expects for `position[...]` fields.

### Step 4 — Verdict (only when asked)

Approve or revoke only when the user explicitly asks for a verdict; a review with findings ends at the notes.

```sh
glab mr approve <id>
glab mr revoke <id>
```

## `glab ci status`

Syntax: `glab ci status [flags]`

| Flag | Purpose |
|------|---------|
| `-b, --branch <branch>` | Branch to check |
| `--live` | Real-time updates until pipeline ends |
| `--compact` | Compact view |
| `-F json` | JSON output (not compatible with `--live`) |

Examples:
```sh
glab ci status -b main
glab ci status -b main --live    # monitor until completion
```

## `glab ci trace`

Syntax: `glab ci trace [flags]`

| Flag | Purpose |
|------|---------|
| `-b, --branch <branch>` | Branch |
| `-p, --pipeline-id <id>` | Pipeline ID |

To trace a specific job, pass the job name or ID as positional argument:
```sh
glab ci trace apply -b main
```

## `glab ci run`

Create a new pipeline:
```sh
glab ci run -b main
```

## Retrying / playing CI jobs

`glab` supports non-interactive retry and play of individual jobs — **always prefer this over creating a new pipeline**.

```sh
# Retry a failed job by name
glab ci retry plan -b main

# Play a manual job by name
glab ci trigger apply -b main

# Use pipeline ID for specificity
glab ci retry plan -b main -p 123456
glab ci trigger apply -b main -p 123456
```

**Exception:** Terraform `apply` jobs consume their `plan` artifact and can only be applied once. If `apply` fails, you must first retry the `plan` job to produce a fresh artifact, then trigger `apply` again.

### Typical Terraform deploy workflow

```sh
# 1. Retry the plan job to get a fresh artifact
glab ci retry plan -b main

# 2. Monitor until plan completes
glab ci status -b main --live

# 3. Trigger the manual apply job
glab ci trigger apply -b main

# 4. Monitor until apply completes
glab ci status -b main --live

# 5. If apply fails, check the trace and repeat from step 1
glab ci trace apply -b main
```

## `glab ci view`

**Do NOT use from Claude Code** — interactive TUI that crashes in non-interactive shells.

## VPN Diagnostics

`sbp.gitlab.schubergphilis.com` requires Cisco Secure Client VPN. When git push fails (403, timeout, connection refused), run this diagnostic before assuming auth issues:

1. Check process: `ps aux | grep -i "[Cc]isco"`
2. Check VPN state: `/opt/cisco/secureclient/bin/vpn state` — look for "Connected"
3. Test reachability: `curl -s -o /dev/null -w "%{http_code}" https://sbp.gitlab.schubergphilis.com/ --max-time 5` — expect 302
4. If disconnected, ask the user to reconnect via Cisco Secure Client
