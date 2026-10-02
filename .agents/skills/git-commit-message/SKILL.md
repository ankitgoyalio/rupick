---
name: git-commit-message
description: Draft or revise Git commit messages in Conventional Commits format. Use when the user asks for a commit message, wants changes summarized for a commit, or needs an existing commit message checked or improved.
---

# Git Commit Message

Produce a message that accurately represents one logical change:

```text
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

## Gather the change

- Use the user's stated intent and supplied diff as the primary evidence.
- In a Git worktree, inspect `git status --short`, the relevant diff, and recent commit subjects when that context is needed. Prefer the staged diff for a pending commit; keep staged and unstaged changes distinct.
- If the evidence contains unrelated changes, propose a separate message for each logical commit instead of hiding them under a vague subject.
- Ask a focused question only when missing intent would materially alter the type, scope, or breaking-change declaration.
- Drafting a message does not authorize staging files, creating a commit, amending history, or pushing.

## Choose the header

- Select the narrowest accurate type. Prefer repository-defined types when available; otherwise use:
  - `feat`: user-visible capability or behavior
  - `fix`: bug correction
  - `perf`: performance improvement
  - `refactor`: internal restructuring without a feature or fix
  - `docs`, `test`, `build`, `ci`, `style`, or `chore`: the corresponding supporting change
  - `revert`: reversal of an earlier change
- Add a short, stable scope only when it helps locate the affected area, such as `parser`, `auth`, or `cli`.
- Add `!` before the colon when the change breaks compatibility.
- Write a concise imperative description that states the outcome. Keep it specific, omit a trailing period, and avoid implementation trivia already obvious from the diff.

## Add context only when useful

- Omit the body for a small, self-explanatory change.
- Use the body to explain motivation, important behavior, or non-obvious tradeoffs. Separate it from the header with one blank line.
- Put issue references, acknowledgements, and other trailers after another blank line.
- For a breaking change that needs migration detail, add a `BREAKING CHANGE: <impact and migration>` footer. The footer must describe what consumers need to change.

## Deliver

Return the ready-to-use commit message without commentary unless the user asks for alternatives or an explanation. Preserve exact multiline formatting. When reviewing an existing message, provide the corrected message first, followed by only the material reasons for the revision.

Examples:

```text
feat(search): add filters for archived results
```

```text
refactor(config)!: replace legacy environment names

Use one canonical name for each deployment environment.

BREAKING CHANGE: rename `qa` to `staging` in deployment configuration.
```
