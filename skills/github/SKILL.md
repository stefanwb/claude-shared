---
name: github
description: Reference for the `gh` CLI tool — PR creation, viewing, inline code review via gh api, and run monitoring. Use when working with GitHub pull requests, reviews, or CI runs.
argument-hint: [pr|review|run]
---

# GitHub `gh` CLI Reference

Always use `gh` for GitHub. Never use `glab` or `lab` for GitHub operations.

## `gh pr create`

```sh
gh pr create --title "Title" --body "$(cat <<'EOF'
## Summary
- What changed and why

## Test plan
- [ ] Item one

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

| Flag | Purpose |
|------|---------|
| `--title` | PR title |
| `--body` | PR body (use HEREDOC to preserve formatting) |
| `--draft` | Open as draft |
| `--base <branch>` | Target branch (default: repo default) |
| `--reviewer <user>` | Request reviewer |

## `gh pr edit`

```sh
gh pr edit 123 --title "Updated title" --body "$(cat <<'EOF'
## Summary
- Updated summary of the current diff

## Test plan
- [ ] Item one
EOF
)"
```

`--body` replaces the whole body. Read the current body first (`gh pr view 123 --json body --jq '.body'`) if you only mean to amend part of it.

## Keeping PRs in sync

**Before asking the user to review a PR, the title and body must describe the current diff.** This is a gate, not a nicety: do not post "ready for review", request a reviewer, or hand the PR back to the user until you have re-read the diff and confirmed the title and body still match it.

This applies to every hand-off, not just the first one. The common miss is **rework**: the user reviews, you push fixes, and you hand the PR back with a title and body still describing the original attempt. Re-run the check after every round of rework, including rebases, force-pushes, scope changes, and commits that drop or add work.

Each time you are about to hand a PR back:

1. `gh pr diff <PR>` — read what the branch actually does now.
2. `gh pr view <PR> --json title,body` — read what the PR currently claims.
3. If they disagree on scope, behaviour, or the test plan, `gh pr edit <PR> --title ... --body ...` before saying anything to the user.
4. Tell the user you refreshed the title/body, so they know the description is current.

Only a push that leaves the diff's scope unchanged — a typo fix, a lint pass, a comment — needs no edit. When in doubt, edit.

## `gh pr view / diff / checks`

```sh
gh pr view 123               # summary + metadata
gh pr view 123 --json number,title,headRefOid   # JSON fields
gh pr diff 123               # full diff
gh pr checks 123             # CI status per check
```

## `gh run`

```sh
gh run list --branch <branch>   # list recent runs
gh run view <id>                # run summary
gh run view <id> --log          # full logs
gh run watch <id>               # stream until complete
```

## Reviewing a PR

**Model and effort.** PR reviews run on Opus at **low** effort. Delegate the review to the `tech-lead` agent; its definition pins `model: opus` and `effort: low`, so it is the default path. `/code-review low` is an alternative only when the session model is already Opus, because `/code-review` runs on the session model. Always type the level: a bare `/code-review` reuses whatever level was typed last, not `low`. Do not review at the session's default (higher) effort and do not switch to another model.

**One reviewer, no fan-out.** A review is a single agent's job. Do not spawn extra agents to split a review by file, dimension, or verification pass. If a change needs a specialist pass (security, cost), name it in the review and let the user decide. This is part of the delegation policy: never more than 2 agents per session without explicit approval (see the `claude-shared` README).

**Workflow.**

1. `gh pr view <PR>` and `gh pr diff <PR>` to read the change.
2. If the title or body no longer matches the diff, refresh it first (see *Keeping PRs in sync*) — a review against a stale description wastes the reviewer's time.
3. Review via `tech-lead` (or `/code-review low` when the session model is Opus). Fewer, high-confidence findings beat broad speculative ones.
4. Post one review with all findings via `gh api` (below). Never split findings across multiple reviews.

## PR Reviews via `gh api`

**Do NOT use `gh pr review`** — it cannot submit inline comments. Use `gh api` for all reviews.

### Step 1 — Fetch the HEAD commit SHA

Always do this immediately before submitting. If the branch updated since you last checked, a stale SHA returns 422.

```sh
gh pr view <PR> --json headRefOid --jq '.headRefOid'
```

### Step 2 — Submit ONE review with body + all inline comments

Never split findings across multiple reviews. The author may commit the first batch before the second lands.

```sh
gh api repos/{owner}/{repo}/pulls/<PR>/reviews \
  --method POST \
  --field commit_id="<SHA>" \
  --field event="COMMENT" \
  --field body="Overall review notes." \
  --field 'comments=[
    {
      "path": "src/foo.py",
      "line": 42,
      "body": "Plain comment on a single line."
    },
    {
      "path": "src/foo.py",
      "start_line": 10,
      "line": 14,
      "body": "Multi-line comment spanning lines 10–14."
    }
  ]'
```

`event` values: `COMMENT` (no verdict), `APPROVE`, `REQUEST_CHANGES`.

### Inline comment line targeting rules

- `line` and `start_line` are **right-side file line numbers** and **must fall within a diff hunk**. Lines outside the diff cannot be targeted.
- To verify a line is in the diff: `gh pr diff <PR>` and check the `@@` hunk headers.
- If a line is not in the diff, write the feedback in the top-level `body` instead — do not attempt an inline comment on that line.

### Suggestion blocks

Suggestions replace the targeted lines when the author clicks "Commit suggestion". Constraints:

- The suggestion can only span lines **inside the diff**. If a fix also requires changing a line outside the diff (e.g., an import at the top of a file that is not in this PR's diff), **do not write a suggestion** — explain the required change in the comment body instead.
- Do not write a suggestion that references or depends on symbols that require edits on non-diff lines.

````
```suggestion
replacement line(s) here
```
````

### Dismiss a review

```sh
gh api repos/{owner}/{repo}/pulls/<PR>/reviews/<review_id>/dismissals \
  --method PUT \
  --field message="Reason for dismissal"
```

Get `review_id`:
```sh
gh api repos/{owner}/{repo}/pulls/<PR>/reviews --jq '.[].id'
```
