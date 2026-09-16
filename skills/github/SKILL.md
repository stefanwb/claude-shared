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

**Model and effort.** PR reviews run on Claude Fable 5.1 at **low** effort. Delegate the review to the `tech-lead` agent (its definition pins `model: fable`, `effort: low`) or run `/code-review low` in the main session. Do not review at the session's default (higher) effort and do not switch to another model.

**One reviewer, no fan-out.** A review is a single agent's job. Do not spawn extra agents to split a review by file, dimension, or verification pass. If a change needs a specialist pass (security, cost), name it in the review and let the user decide. This is part of the delegation policy: never more than 2 agents per session without explicit approval (see the `claude-shared` README).

**Workflow.**

1. `gh pr view <PR>` and `gh pr diff <PR>` to read the change.
2. Review (tech-lead or `/code-review low`). Fewer, high-confidence findings beat broad speculative ones.
3. Post one review with all findings via `gh api` (below). Never split findings across multiple reviews.

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
