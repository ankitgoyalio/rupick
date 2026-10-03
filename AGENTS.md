## Agent skills

### Issue tracker

Track issues and specs in GitHub Issues. Read `docs/agents/issue-tracker.md` before tracker operations.

### Triage labels

Use the five default triage labels. Read `docs/agents/triage-labels.md` before applying triage labels.

### Domain docs

Use a single-context layout: root `GLOSSARY.md` and `docs/adr/`. Read `docs/agents/domain.md` before exploring the codebase.

## Documentation audience

Keep `README.md` focused on human-facing project usage. Put agent workflows and completion criteria in `AGENTS.md`.

## Swift formatting

Before submitting Swift changes:

1. Run `./scripts/format.sh` from the repository root and review every changed file for unintended edits.
2. Run `./scripts/lint-format.sh`; formatting is complete when it exits successfully.

Use these scripts for the pinned formatter and repository config; they isolate formatting from personal settings and Xcode builds. The first run downloads and builds the formatter. CI uses the same lint command.

When changing formatting tooling, consult `BuildTools/Package.swift` and `BuildTools/Package.resolved` for the version, and `.swiftformat` for rules and exclusions. Preserve the `preferKeyPath` exception unless the full test suite confirms closure conversions inside Swift Testing macros compile.
