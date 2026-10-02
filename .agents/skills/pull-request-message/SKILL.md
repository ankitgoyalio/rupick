---
name: pull-request-message
description: Draft or revise pull request and merge request descriptions using a What / Why / How structure. Use when the user asks for a PR or MR message, description, summary, or template content.
---

# Pull Request Message

Produce an accurate, reviewer-oriented description with these required sections:

```markdown
## What

<What changed?>

## Why

<Why is this necessary?>

## How

<How was it implemented?>
```

Add any useful optional sections after `How`, in this order:

```markdown
## Testing

## Screenshots

## Risks

## Rollback
```

## Gather the change

- Use the user's intent, issue context, and supplied diff as the primary evidence.
- In a Git worktree, inspect the repository's PR or MR template and compare the complete branch against its intended base when that context is needed. Distinguish committed branch changes from uncommitted work that would not be included.
- Account for every material change in the comparison. Ask a focused question only when missing context would make the description misleading, especially the business reason or intended base.
- Drafting a description does not authorize creating, updating, or merging a PR or MR.

## Write the required sections

- `What`: summarize observable behavior, API, data, configuration, or operational changes. Group related changes into concise bullets when there is more than one; avoid a file-by-file inventory.
- `Why`: state the problem, user need, or engineering constraint that makes the change necessary. Explain the outcome sought rather than repeating `What`.
- `How`: describe the important implementation approach and design decisions at reviewer depth. Include details that help validate the change; omit incidental mechanics visible directly in the diff.

## Select optional sections

- `Testing`: report the exact automated or manual checks and their outcomes. State that testing was not run, with the reason, when that fact is important. Never invent test execution or results.
- `Screenshots`: include supplied or generated evidence for visible UI changes. Use clear before/after labels when both exist; omit the section when it adds no review value.
- `Risks`: identify concrete compatibility, migration, rollout, performance, security, or operational risks and their mitigations. Avoid generic claims such as "low risk."
- `Rollback`: give the practical reversal path when it is more involved than reverting the change, including feature flags, schema compatibility, or deployment ordering as applicable.

## Deliver

Return ready-to-paste Markdown without commentary unless the user asks for alternatives or an explanation. Preserve repository-required metadata when a local template supplies it, while retaining the `What`, `Why`, and `How` sections. Provide a PR or MR title only when requested.
