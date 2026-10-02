# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `ankitgoyalio/rupick`.
Use the `gh` CLI from this clone; it infers the repository from the remote.

## Conventions

- Create: `gh issue create --title "..." --body-file <file>`
- Read: `gh issue view <number> --json number,title,body,labels,comments`
- List: `gh issue list --state open --json number,title,body,labels,comments`
  with appropriate label and state filters.
- Comment: `gh issue comment <number> --body-file <file>`
- Apply labels: `gh issue edit <number> --add-label "..."`
- Remove labels: `gh issue edit <number> --remove-label "..."`
- Close: `gh issue close <number> --comment "..."`

For multiline bodies, write the exact text to a temporary file and use
`--body-file`.

## Pull requests as a triage surface

PRs as a request surface: no.

GitHub shares issue and PR numbers. Resolve an ambiguous number with
`gh pr view <number>`, falling back to `gh issue view <number>`.

## Skill operations

When a skill says "publish to the issue tracker", create a GitHub issue.
When it says "fetch the relevant ticket", read the issue and its comments.

## Wayfinding operations

- Map: one issue labelled `wayfinder:map`, containing Notes,
  Decisions-so-far, and Fog.
- Child tickets: link issues as GitHub sub-issues. If unavailable, use
  a task list in the map and `Part of #<map>` in each child.
  Label children `wayfinder:<type>` for research, prototype, grilling,
  or task.
- Blocking: use native GitHub issue dependencies. Add a dependency with
  `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`.
  Obtain the database ID with
  `gh api repos/<owner>/<repo>/issues/<number> --jq .id`.
  If unavailable, add `Blocked by: #<number>` to the child.
- Frontier: inspect the map's open children in map order. Select the
  first unassigned ticket whose blockers are all closed. For native
  dependencies, `issue_dependencies_summary.blocked_by` counts open blockers.
- Claim: `gh issue edit <number> --add-assignee @me`.
- Resolve: comment with the answer, close the ticket, and append a
  summary and link to the map's Decisions-so-far.
