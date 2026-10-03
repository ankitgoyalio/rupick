## Agent skills

Read the linked `SKILL.md` when its trigger applies; load supporting references as needed. Skills marked **explicit** require user invocation.

### UI design and copy

- [apple-design](.agents/skills/apple-design/SKILL.md): Apple-style gestures, materials, typography, and physical motion.
- [emil-design-eng](.agents/skills/emil-design-eng/SKILL.md): UI polish and component design.
- [app-ux-writing](.agents/skills/app-ux-writing/SKILL.md): Write or review app interface copy and control names.
- [break-ui](.agents/skills/break-ui/SKILL.md): Stress-test UI with extreme or missing data.

### Animation and motion

- [animate](.agents/skills/animate/SKILL.md): Implement animations and transitions.
- [animation-vocabulary](.agents/skills/animation-vocabulary/SKILL.md): Identify the name of a described motion effect.
- [find-animation-opportunities](.agents/skills/find-animation-opportunities/SKILL.md): Propose places to add motion.
- [improve-animations](.agents/skills/improve-animations/SKILL.md): Audit existing motion and plan improvements.
- [review-animations](.agents/skills/review-animations/SKILL.md) (**explicit**): Review animation code.

### Architecture and domain modeling

- [codebase-design](.agents/skills/codebase-design/SKILL.md): Design module interfaces, boundaries, and testability.
- [improve-codebase-architecture](.agents/skills/improve-codebase-architecture/SKILL.md) (**explicit**): Find module deepening opportunities and examine a selected design.
- [domain-modeling](.agents/skills/domain-modeling/SKILL.md): Define domain vocabulary, maintain the glossary, and record ADRs.

### Implementation, debugging, and testing

- [implement](.agents/skills/implement/SKILL.md) (**explicit**): Implement a spec or tickets.
- [diagnosing-bugs](.agents/skills/diagnosing-bugs/SKILL.md): Diagnose failures and performance regressions.
- [tdd](.agents/skills/tdd/SKILL.md): Develop test-first or add integration tests.
- [write-swift](.agents/skills/write-swift/SKILL.md): Write, review, or migrate Swift code.

### Planning and issue management

- [grilling](.agents/skills/grilling/SKILL.md): Stress-test a plan or decision through questions.
- [grill-with-docs](.agents/skills/grill-with-docs/SKILL.md) (**explicit**): Sharpen a design through questions while recording domain docs.
- [to-spec](.agents/skills/to-spec/SKILL.md) (**explicit**): Synthesize the conversation into a tracker spec.
- [to-tickets](.agents/skills/to-tickets/SKILL.md) (**explicit**): Split a plan into tickets with dependencies.
- [triage](.agents/skills/triage/SKILL.md) (**explicit**): Triage issues and external PRs into actionable briefs.

### Review and delivery

- [code-review](.agents/skills/code-review/SKILL.md): Review changes against repository standards and the originating spec.
- [git-commit-message](.agents/skills/git-commit-message/SKILL.md): Draft or revise Conventional Commit messages.
- [pull-request-message](.agents/skills/pull-request-message/SKILL.md): Draft or revise PR and MR descriptions.
- [handoff](.agents/skills/handoff/SKILL.md) (**explicit**): Prepare a conversation handoff for another agent.

### Setup and guided workflows

- [setup-matt-pocock-skills](.agents/skills/setup-matt-pocock-skills/SKILL.md) (**explicit**): Configure the issue tracker, triage labels, and domain doc layout.
- [wizard](.agents/skills/wizard/SKILL.md): Build a guided shell wizard for steps a human must perform.

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

## Punctuation

Use periods, commas, colons, or parentheses in copy, documentation, comments, and messages. Em dashes (Unicode U+2014) are prohibited throughout this project and in responses about it.
