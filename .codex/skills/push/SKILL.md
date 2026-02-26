---
name: push
description:
  Push current branch changes to origin and create or update the corresponding
  pull request; use when asked to push, publish updates, or create pull request.
---

# Push

## Prerequisites

- `gh` CLI is installed and available in `PATH`.
- `gh auth status` succeeds for GitHub operations in this repo.

## Goals

- Push current branch changes to `origin` safely.
- Create a PR if none exists for the branch, otherwise update the existing PR.
- Keep branch history clean when remote has moved.

## Related Skills

- `pull`: use this when push is rejected or sync is not clean (non-fast-forward,
  merge conflict risk, or stale branch).

## Steps

1. Identify current branch and confirm remote state.
2. Run local validation (`make -C elixir all`) before pushing.
3. Push branch to `origin` with upstream tracking if needed, using whatever
   remote URL is already configured.
4. If push is not clean/rejected:
   - If the failure is due to auth or workflow limitations on the configured
     remote (for example, updating workflow files over HTTPS/token auth),
     retry the push over SSH before treating it as a sync problem.
   - Check the current SSH agent with `ssh-add -L`.
   - If no keys are available there, check `/tmp/ssh-dev-user.sock`.
   - Retry the push with the repo SSH URL.
   - If the failure is a non-fast-forward or sync problem, run the `pull`
     skill to merge `origin/main`, resolve conflicts, and rerun validation.
   - Push again; use `--force-with-lease` only when history was rewritten.

5. Ensure a PR exists for the branch:
   - If no PR exists, create one.
   - If a PR exists and is open, update it.
   - If branch is tied to a closed/merged PR, create a new branch + PR.
   - Write a proper PR title that clearly describes the change outcome
   - For branch updates, explicitly reconsider whether current PR title still
     matches the latest scope; update it if it no longer does.
6. Write/update PR body explicitly using `.github/pull_request_template.md`:
   - Fill every section with concrete content for this change.
   - Replace all placeholder comments (`<!-- ... -->`).
   - Keep bullets/checkboxes where template expects them.
   - If PR already exists, refresh body content so it reflects the total PR
     scope (all intended work on the branch), not just the newest commits,
     including newly added work, removed work, or changed approach.
   - Do not reuse stale description text from earlier iterations.
7. Validate PR body with `mix pr_body.check` and fix all reported issues.
8. Reply with the PR URL from `gh pr view`.

## Commands

```sh
# Identify branch
branch=$(git branch --show-current)

# Minimal validation gate
make -C elixir all

ssh_url=org-14957082@github.com:openai/symphony.git

ssh_fallback_push() {
  if ssh-add -L >/dev/null 2>&1; then
    git push -u "$ssh_url" HEAD
    return
  fi

  if [ -S /tmp/ssh-dev-user.sock ] && \
    SSH_AUTH_SOCK=/tmp/ssh-dev-user.sock ssh-add -L >/dev/null 2>&1; then
    SSH_AUTH_SOCK=/tmp/ssh-dev-user.sock git push -u "$ssh_url" HEAD
    return
  fi

  echo "No SSH agent available for fallback push." >&2
  return 1
}

# Initial push: respect the current origin remote first.
git push -u origin HEAD

# If that failed because the current remote auth cannot perform the push
# (for example, workflow file updates over HTTPS/token auth), retry over SSH:
ssh_fallback_push

# If that failed because the remote moved, use the pull skill. After
# pull-skill resolution and re-validation, retry the normal push:
git push -u origin HEAD

# Only if history was rewritten locally:
git push --force-with-lease origin HEAD

# Ensure a PR exists (create only if missing)
pr_state=$(gh pr view --json state -q .state 2>/dev/null || true)
if [ "$pr_state" = "MERGED" ] || [ "$pr_state" = "CLOSED" ]; then
  echo "Current branch is tied to a closed PR; create a new branch + PR." >&2
  exit 1
fi

# Write a clear, human-friendly title that summarizes the shipped change.
pr_title="<clear PR title written for this change>"
if [ -z "$pr_state" ]; then
  gh pr create --title "$pr_title"
else
  # Reconsider title on every branch update; edit if scope shifted.
  gh pr edit --title "$pr_title"
fi

# Write/edit PR body to match .github/pull_request_template.md before validation.
# Example workflow:
# 1) open the template and draft body content for this PR
# 2) gh pr edit --body-file /tmp/pr_body.md
# 3) for branch updates, re-check that title/body still match current diff

tmp_pr_body=$(mktemp)
gh pr view --json body -q .body > "$tmp_pr_body"
(cd elixir && mix pr_body.check --file "$tmp_pr_body")
rm -f "$tmp_pr_body"

# Show PR URL for the reply
gh pr view --json url -q .url
```

## Git Remote Failure Fallback

- Prefer whatever URL is already configured on `origin`; do not rewrite the
  remote just to prefer SSH or HTTPS.
- First try `git push -u origin HEAD` normally.
- If that fails because the current auth method cannot perform the operation
  (for example, workflow file updates rejected over HTTPS/token auth), retry
  over SSH with `org-14957082@github.com:openai/symphony.git`.
- Check the active SSH agent first with `ssh-add -L`.
- If no agent keys are available, try the known fallback socket:
  - `SSH_AUTH_SOCK=/tmp/ssh-dev-user.sock ssh-add -L`
  - `SSH_AUTH_SOCK=/tmp/ssh-dev-user.sock git push -u org-14957082@github.com:openai/symphony.git HEAD`
- Leave `origin` unchanged unless there is a specific need to set a persistent
  SSH push URL for repeated retries.
- If SSH fallback is unavailable or also fails, stop and surface the exact
  error instead of silently changing remotes.

## Notes

- Do not use `--force`; only use `--force-with-lease` as the last resort.
- Remote/auth fallback for push failures:
  - Start with the configured `origin` remote.
  - Use SSH fallback only for auth/workflow-limit failures on that remote.
  - Probe the current SSH agent first, then `/tmp/ssh-dev-user.sock`.
