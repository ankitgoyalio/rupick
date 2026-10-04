# Project skill audit

Reviewed on 2026-10-04 against [Paul Solt's article](https://x.com/PaulSolt/status/2042716870512353294) and the upstream repositories. Selection is a project-fit judgment based on the actual instructions, reference coverage, tool assumptions, and overlap. It is not a measured comparison of generated code quality.

## Scope and criteria

Rupick is a macOS 15+ SwiftUI app with AppKit panels, Observation, background image processing, Swift Testing unit/session tests, and XCTest UI automation. The app uses Swift 6 language mode, approachable concurrency, and nonisolated default actor isolation. The app has no SwiftData, Core Data, CloudKit, iOS target, or runtime package dependency graph. `BuildTools` is a separate formatter package.

This audit covers the 27 skills committed under `.agents/skills` and all five article packs. It does not modify user-global skills, system skills, or runtime-injected plugins, which cannot be delivered through this repository's PR.

Prefer native macOS guidance, settings-aware concurrency, focused topic references, compatible licenses, and workflows that complement the existing tracker, glossary, ADR, formatting, and acceptance setup. Keep one primary skill for each technical topic.

## Article comparison

| Article candidate | Decision | Project-specific reason |
| --- | --- | --- |
| [Hudson SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill) | Use SwiftLee instead | Hudson's compact review checklist is useful, but its core defaults target iOS 26 and Swift 6.2+. SwiftLee explicitly supports macOS, provides separate scene/window/view references, and covers implementation, animation, accessibility, and Instruments. |
| [Hudson Concurrency Pro](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) | Use SwiftLee instead | Both have cancellation, actors, and structured-concurrency references. SwiftLee starts by inspecting language mode, isolation, and upcoming-feature settings, and maps diagnostics to the smallest safe fix. This fits Rupick's explicit isolation policy better than a fixed minimum-language default. |
| [Hudson Testing Pro](https://github.com/twostraws/Swift-Testing-Agent-Skill) | Use SwiftLee instead | Both support modern assertions and keep UI automation on XCTest. SwiftLee also calls out XCTest-only performance metrics, parallel test isolation, test-plan filtering, and flaky-test diagnosis. Install one testing authority. |
| [Hudson SwiftData Pro](https://github.com/twostraws/SwiftData-Agent-Skill) | Omit | No persistent model store. Its preference for SwiftData would introduce an unrelated architectural default. Revisit when persistence is designed. |
| [SwiftLee SwiftUI Expert](https://github.com/AvdLee/SwiftUI-Agent-Skill) | Install | Replaces web-oriented UI and motion guidance with native SwiftUI references, including macOS scenes, windows, and AppKit interop. |
| [SwiftLee Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) | Install | Replaces the concurrency and migration sections of `write-swift` with dedicated settings-aware diagnostics and references. |
| [SwiftLee Testing Expert](https://github.com/AvdLee/Swift-Testing-Agent-Skill) | Install | Replaces the testing section of `write-swift`; complements `tdd`, which governs the development process rather than framework APIs. |
| [SwiftLee Core Data Expert](https://github.com/AvdLee/Core-Data-Agent-Skill) | Omit | No Core Data stack or migrations. Revisit if a persistent store adopts it. |
| [SwiftLee Xcode Build Optimization](https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill) | Defer | Six coordinated benchmark/analyzer/fixer skills address measured build bottlenecks. This task does not establish a build-performance problem; adding that entire workflow is unnecessary for skill cleanup. Revisit for an actual slow-build report, benchmark first, and install its cooperating skills together. |
| [OpenAI Build iOS Apps](https://github.com/openai/plugins/tree/main/plugins/build-ios-apps) | Omit | Simulator debugging, App Intents, and iOS profiling are outside this macOS app. Its SwiftUI patterns/refactor/performance topics overlap the selected SwiftUI skill. |
| [OpenAI Build macOS Apps](https://github.com/openai/plugins/tree/main/plugins/build-macos-apps) | Defer full plugin | Scene/window/AppKit/refactor guidance overlaps SwiftLee. Build/run bootstrap creates Codex-specific environment wiring; SwiftPM app bundling does not match this Xcode app. Packaging, notarization, signing, and telemetry are useful for future release or diagnostics work, not reasons to install all eleven skills now. |
| [Zablocki rules](https://merowing.info/posts/stop-getting-average-code-from-your-llm/) | Omit | The public `general.md` and `rule-loading.md` duplicate architecture, dependency, test, and commit guidance. The loader references rule files not supplied by the two downloads; the full set belongs to the course. Its always-clarify architecture workflow is a poor fit for routine implementation here. |
| [AppCreator](https://super-easy-apps.kit.com/app-creator) | Not installed, content unverified | The public page offers a signup form, not a directly inspectable skill or public source. No email signup was submitted. Rupick already has synchronized Xcode folders, a documented native test command, and pinned formatter scripts. The landing page alone cannot establish that the skill is better. |

The community Swift skill directory is a discovery index, not a skill to install. RocketSim and Inject are development tools mentioned alongside the packs; this project has no iOS simulator target and no hot-reload requirement.

## Existing skill decisions

Every previously installed skill is accounted for below. The project now has 21 skills: 18 retained, 9 removed, and 3 added.

| Existing skills | Decision | Reason |
| --- | --- | --- |
| `apple-design`, `emil-design-eng` | Remove | Despite the Apple-oriented names and useful design principles, their implementation rules prescribe CSS, Pointer Events, browser rendering, and web animation libraries. Native SwiftUI references fit this app better. |
| `animate`, `find-animation-opportunities`, `improve-animations`, `review-animations` | Remove | Overlapping web motion workflows with CSS/React property rules and browser inspection. SwiftUI Expert includes basic, transition, advanced, and reduced-motion guidance. Keep the concrete motion behavior recorded in acceptance docs. |
| `animation-vocabulary` | Remove | Web-only glossary references a nonexistent project `/vocabulary` page and requires verbatim terminology. Native motion reference files are sufficient here. |
| `break-ui` | Remove | Mandates HTML/browser layout checks, CSS fixes, and a demo toggle. Rupick already has native debug stress fixtures and acceptance coverage for long, Unicode, empty, single, and large datasets. Preserve that coverage. |
| `setup-matt-pocock-skills` | Remove | One-time setup is complete: tracker, labels, glossary, and ADR layout exist. Redirect dependent workflows to the committed configuration docs. |
| `write-swift` | Retain, narrow | Value modeling, errors, protocols, generics, API design, ARC, macros, logging, and interop remain useful. Remove duplicated concurrency/migration/testing sections and route those tasks to their specialists. |
| `app-ux-writing` | Retain | Apple-oriented interface copy, control naming, and voice guidance are distinct from SwiftUI correctness. |
| `codebase-design`, `improve-codebase-architecture`, `domain-modeling` | Retain | Module depth, architecture exploration, and domain vocabulary/ADRs are complementary workflows used by the repository. |
| `diagnosing-bugs`, `tdd`, `implement` | Retain | Reproduction loops, behavior-first tests, and spec/ticket execution complement the technical specialists. General examples do not impose a browser-only implementation. |
| `grilling`, `grill-with-docs` | Retain | The latter composes questioning with domain documentation. It delegates to the former rather than duplicating its interviewing rules. |
| `to-spec`, `to-tickets`, `triage` | Retain | Separate GitHub issue synthesis, dependency planning, and triage operations using the configured tracker. |
| `code-review`, `git-commit-message`, `pull-request-message` | Retain | Repository/spec review and delivery conventions remain relevant regardless of platform. |
| `handoff`, `wizard` | Retain | Context handoff and guided steps that only a human can perform are distinct optional workflows. |

## Installed sources and local adaptations

All three new skills are MIT-licensed. Each installed directory includes its upstream `LICENSE`, references, and any required scripts/assets. Exact audited revisions:

| Skill | Source | Revision |
| --- | --- | --- |
| `swiftui-expert-skill` | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill/tree/9897311e3e42cc77e87603226e74bea711092fbd/skills/swiftui-expert-skill) | `9897311e3e42cc77e87603226e74bea711092fbd` |
| `swift-concurrency` | [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill/tree/d5770817d2622e1585b1f7eaebc791a9cb0959c8/skills/swift-concurrency) | `d5770817d2622e1585b1f7eaebc791a9cb0959c8` |
| `swift-testing-expert` | [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill/tree/798e9b1a2bcac164d4f0c781908199e754f0bab6/swift-testing-expert) | `798e9b1a2bcac164d4f0c781908199e754f0bab6` |

`skills-lock.json` uses the skills CLI format. For the new skills, `ref` pins the audited upstream commit and `computedHash` records the original upstream folder hash (SHA-256 of locale-sorted relative paths and file bytes). It deliberately describes the source snapshot, not the locally adapted payload. Git records the adaptations. Existing source hashes retain their previous meaning.

Local adaptations:

- Normalize prohibited em dash punctuation in imported text and script messages to commas, preserving licenses verbatim.
- Correct the concurrency router's task-group summary: normal `withTaskGroup` scope exit waits for children rather than automatically cancelling them.
- Shorten SwiftUI Expert's description to the macOS topics that can trigger it here. Keep its full topic references for selective loading.
- Narrow `write-swift`, remove its obsolete greeting/toolchain baseline and overlapping sections, and route concurrency/testing to the installed specialists. Treat toolchain-sensitive syntax as requiring verification.
- Redirect `code-review`, `to-spec`, `to-tickets`, and `triage` from the deleted setup command to `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md`.
- Update acceptance documentation to retain the recorded motion review and concrete behavior without depending on the removed review skill.

Skills contain recommendations and examples. Project instructions, the installed SDK, build diagnostics, and tests resolve conflicts. In particular, preserve macOS 15 fallbacks, background image processing, per-window session ownership, and XCTest UI automation. Adding a skill does not authorize an app architecture or build-setting migration.

## Maintenance

Before upgrading, review the upstream diff from the pinned revision, its license, scripts, and local adaptations above. Use the skill-installer helper with `--repo`, `--ref`, `--path`, and `--dest .agents/skills` for repository-local installs; stage replacements outside the existing destination first. Reapply documented adaptations and refresh the source revision/hash together. A generic skills CLI update or restore may overwrite adaptations; inspect its full diff before committing.

When adding/removing skills, update the AGENTS index, lockfile, this decision table, and consumer references together. Validate that the index, installed directories, and lock keys agree, that referenced local files exist, and that imported scripts parse. Run the repository format lint for delivery. App build/test execution is needed when application code or build configuration changes; this audit changes neither.
