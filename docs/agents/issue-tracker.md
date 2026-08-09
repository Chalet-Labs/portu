# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

> Mutations (`create`, `comment`, `edit --add-label`/`--remove-label`, `close`) require `issues: write` on the calling token. This repo's CI workflows only grant `issues: read` — run mutations from a user-authenticated local `gh` session instead.

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments` for a human-readable view, or `gh issue view <number> --json number,title,body,labels,comments --jq '{number, title, body, labels: [.labels[].name], comments: [.comments[].body]}'` for structured output (`--jq` requires `--json`; it cannot filter the `--comments` text view).
- **List issues**: `gh issue list --state open --limit 200 --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters. `--limit` defaults to 30 — pass an explicit higher value so the list isn't silently truncated on repos with more open issues. This also truncates each issue's `comments` at 100 (verified: `gh issue list --json comments` capped a 993-comment issue at 100, while `gh issue view <number> --json comments` on the same issue returned all 993) — for an issue that might have more, re-fetch its comments with **Read an issue** instead of trusting the list's inline copy.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v` — `gh` does this automatically when run inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `authorAssociation` isn't a supported `gh pr list --json` field, so use the REST API instead: `gh api "repos/{owner}/{repo}/pulls?state=open" --paginate --jq '.[] | {number, title, author: .user.login, authorAssociation: .author_association}'` (`--paginate` walks every page instead of the 30-item default `--limit`). Keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, `FIRST_TIMER`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`). `FIRST_TIMER` (never contributed to any repo the org owns) is distinct from `FIRST_TIME_CONTRIBUTOR` (first contribution to this repo) — both need to stay in triage.
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either — resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

> `gh issue create --label`/`gh issue edit --add-label` attaches an existing label — it does not create one. Provision `wayfinder:map` and the four `wayfinder:<type>` labels (`gh label create wayfinder:map`, etc.) before the first map or child ticket; none of them exist in this repo's tracker yet.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies** — the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only — the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: paginate the map's children via `gh api graphql` on the `subIssues(first: 100, after: $cursor)` connection, following `pageInfo.hasNextPage`/`endCursor` — `gh issue view --json subIssues` silently truncates past 100 children with no cursor. Keep only `state: OPEN` nodes (a closed, unassigned child must not re-enter the frontier), in map order — not `gh issue list --state open`, which returns repository issue-list order rather than the map's child ordering (the fallback task list's order works too, skipping completed entries). Drop any remaining child with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me` — the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
