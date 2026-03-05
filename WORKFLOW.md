---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: d9873e6beee9
  active_states: Review, Prepare, Merge
  terminal_states: Done, Canceled, Duplicate

polling:
  interval_ms: 30000

workspace:
  root: ~/Projects/caclawphony/workspaces

hooks:
  after_create: |
    git clone /Users/phaedrus/Projects/openclaw . 2>/dev/null || true
    # Extract PR number from issue title (format: "PR #1234: title" or "#1234")
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || git checkout main
    fi
  before_run: |
    # Ensure we're on the right branch and up to date
    PR_NUM=$(echo "$SYMPHONY_ISSUE_TITLE" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
    if [ -n "$PR_NUM" ]; then
      gh pr checkout "$PR_NUM" --force 2>/dev/null || true
      git pull --rebase origin HEAD 2>/dev/null || true
    fi
  timeout_ms: 120000

agent:
  max_concurrent_agents: 4
  max_turns: 20
  max_retry_backoff_ms: 300000
  max_concurrent_agents_by_state:
    prepare: 1

codex:
  command: codex app-server
  approval_policy: on-failure
  read_timeout_ms: 30000
  turn_timeout_ms: 1800000
  stall_timeout_ms: 300000
  thread_sandbox: danger-full-access
---

# Caclawphony — openclaw/openclaw PR Pipeline

You are a maintainer working on the openclaw/openclaw repository.

## Issue Context

- **Issue:** {{ issue.identifier }} — {{ issue.title }}
- **Description:** {{ issue.description }}
- **State:** {{ issue.state }}
{% if attempt %}- **Attempt:** {{ attempt }}{% endif %}

## Your Task

{% if issue.state == "Review" %}
### Review Phase

Run `review-pr` on this PR. Read the skill file at `.agents/skills/review-pr/SKILL.md` and follow its instructions exactly.

Your output should be:
1. A `.local/review.md` file with findings
2. A `.local/review.json` file with structured results

Do NOT comment on the PR. Do NOT push any changes. This is a read-only review.

When finished, transition this issue to **Review Complete** using the Linear GraphQL tool:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "4f363475-bf45-48a0-9466-c38eef79aded" }) { success } }
```

{% elsif issue.state == "Prepare" %}
### Prepare Phase

Run `prepare-pr` on this PR. Read the skill file at `.agents/skills/prepare-pr/SKILL.md` and follow its instructions exactly.

This phase:
1. Rebases the PR onto main
2. Fixes any BLOCKER or IMPORTANT findings from the review
3. Runs the gate checks (build, test, lint)
4. Pushes the result

When finished, transition this issue to **Prepare Complete**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "0671e7cc-46b5-424e-aed3-d9408c9d3eb9" }) { success } }
```

{% elsif issue.state == "Merge" %}
### Merge Phase

Run `merge-pr` on this PR. Read the skill file at `.agents/skills/merge-pr/SKILL.md` and follow its instructions exactly.

This phase:
1. Performs a deterministic squash merge
2. Adds proper attribution and co-author trailers
3. Cleans up the branch

When finished, transition this issue to **Done**:
```
mutation { issueUpdate(id: "{{ issue.id }}", input: { stateId: "e085693d-8142-4671-9de5-20286fae8ec6" }) { success } }
```

{% endif %}

## Rules

- Never comment on the PR on GitHub without explicit approval
- Follow the skill instructions exactly — they contain the authoritative process
- If you encounter an error you can't resolve, leave a comment on the Linear issue explaining what went wrong
