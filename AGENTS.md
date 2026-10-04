## Agent skills

Read the linked `SKILL.md` when its trigger applies; load supporting references as needed. Skills marked **explicit** require user invocation.

### SwiftUI and interface copy

- [swiftui-expert-skill](.agents/skills/swiftui-expert-skill/SKILL.md): SwiftUI state, macOS scenes and windows, layout, accessibility, animation, and performance.
- [app-ux-writing](.agents/skills/app-ux-writing/SKILL.md): Write or review app interface copy and control names.

### Architecture and domain modeling

- [codebase-design](.agents/skills/codebase-design/SKILL.md): Design module interfaces, boundaries, and testability.
- [improve-codebase-architecture](.agents/skills/improve-codebase-architecture/SKILL.md) (**explicit**): Find module deepening opportunities and examine a selected design.
- [domain-modeling](.agents/skills/domain-modeling/SKILL.md): Define domain vocabulary, maintain the glossary, and record ADRs.

### Implementation, debugging, and testing

- [implement](.agents/skills/implement/SKILL.md) (**explicit**): Implement a spec or tickets.
- [diagnosing-bugs](.agents/skills/diagnosing-bugs/SKILL.md): Diagnose failures and performance regressions.
- [tdd](.agents/skills/tdd/SKILL.md): Develop test-first or add integration tests.
- [write-swift](.agents/skills/write-swift/SKILL.md): Swift value modeling, protocols, API design, ARC, performance, and interop.
- [swift-concurrency](.agents/skills/swift-concurrency/SKILL.md): Tasks, actors, Sendable, cancellation, isolation diagnostics, and Swift 6 migration.
- [swift-testing-expert](.agents/skills/swift-testing-expert/SKILL.md): Swift Testing assertions, parameterization, async waiting, isolation, and XCTest migration.

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

### Guided workflows

- [wizard](.agents/skills/wizard/SKILL.md): Build a guided shell wizard for steps a human must perform.

### Project skill scope

Use project settings and the installed SDK as the authority for language features and API availability. Preserve macOS 15 support, per-window sessions, explicit UI isolation, and background image processing from the implementation ADR. General skill defaults do not authorize changing actor-isolation settings or deployment targets.

Use `swift-concurrency` for concurrency and migration, `swift-testing-expert` for test APIs, and `tdd` for the test-first process. Keep XCTest for native UI automation and XCTest-only metrics. Use native SwiftUI motion references and preserve the behavior documented in `docs/acceptance.md`.

See [the skill audit and maintenance notes](docs/agents/skills.md) for selection rationale, source revisions, and local adaptations. Repository skills live in `.agents/skills`; user-global and runtime-provided skills are managed separately.

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
