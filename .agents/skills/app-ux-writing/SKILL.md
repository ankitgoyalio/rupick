---
name: app-ux-writing
description: Plan, write, review, and implement app interface copy using WWDC UX writing principles. Use for screen and flow copy, microcopy, app voice and tone, and feature or control naming; Apple platforms first, adaptable elsewhere. Excludes marketing copy and standalone product or company naming.
---

# App UX Writing

Design language as part of the interaction: what people need to understand, how they act, and when information appears. Apply the app's own voice and values. Apple examples inform the method without prescribing Apple's personality for every product.

## Establish the task

Match the requested work: plan a flow, draft copy, review existing language, name something within an app, or implement changes. A copy review produces recommendations; a request to edit or implement produces changes in the relevant files.

Inspect the supplied screens, flow, source strings, nearby controls, existing writing guidance, and terminology as needed. Establish the audience, user goal, platform, actual behavior, and relevant states. For a single label, use its immediate context; for a flow, follow its entry, decisions, and outcome. Reuse available context and ask only about gaps that materially affect the result.

Look for `WORD_LIST.md` in the project root or the app's documentation. If available, read the list applicable to the app before drafting, reviewing, naming, or implementing copy, and use it as the terminology reference. If absent, follow existing writing guidance and established UI terms; its absence does not block the task.

Ground promises in supplied requirements or implementation. Confirm facts such as deletion scope, retained access, timing, permissions, and privacy before stating them. When behavior is unknown, flag the specific gap and keep dependent wording provisional. Desired feelings of security are not evidence of encryption or privacy guarantees.

## Design with PACE

Use these four lenses at the scope of the task:

- **Purpose:** Identify the one most important thing to understand or do on each screen and how it serves the flow. Make the heading and actions understandable when scanned. Keep supporting text for distinct information; move secondary detail to the point where it is useful. Retain information necessary for an informed choice.
- **Anticipation:** Treat the flow as a conversation. Answer the next likely question, explain what an action will do, and distinguish an intermediate state from completion. Keep the voice consistent while adapting tone to the moment.
- **Context:** Consider attention, device, surroundings, and emotional stakes. Put instructions near the relevant interaction and at the time they are needed. Surface decisions as interruptions only when the interaction requires them. Identify a timing or hierarchy problem when wording alone cannot solve it.
- **Empathy:** Use accessible, inclusive language appropriate to the audience. Avoid assuming a task is easy, someone is happy, or everyone shares a cultural reference. Consider localization and the experience when content is heard through a screen reader.

When establishing or changing a voice, or resolving a tone mismatch, read [Voice and tone](references/voice-and-tone.md). When naming a feature, tab, setting, plan, or action, read [Naming within an app](references/naming.md). When writing or reviewing screen copy, read the relevant sections of [Interface patterns](references/interface-patterns.md).

## Write and refine

1. Express the useful message accurately, in the app's vocabulary. Lead with the benefit when it helps explain a requested action; lead with the event, consequence, or instruction when that is the person's immediate need.
2. Remove filler, repeated ideas, and unsupported claims about ease or speed. Preserve modifiers that explain behavior, detail needed for recovery or consent, and repetition that keeps terminology unambiguous. Warmth and celebration can earn their space when they fit the moment.
3. Read the heading and actions alone, then the complete screen and adjacent steps in sequence. Check conversational rhythm as if reading aloud, ambiguity, repetitive wording, and whether the next step matches what the copy promises.
4. Check related uses of a changed term within scope against the word list. When establishing terminology, add or propose a focused entry using the format below.

## Word list

Use three columns in `WORD_LIST.md`:

| Use | Avoid | Definition |
| --- | --- | --- |
| Saved Trails | Favorites, Bookmarks | Trails the person saves to find later. Saving does not download an offline map. |

The row illustrates the format; use the app's actual terms and behavior. `Use` records the preferred term, including button labels where useful. `Avoid` lists alternatives for that same concept, not words banned throughout the app. `Definition` explains the concept and any distinction needed to apply it correctly. Preserve meaningful differences such as removing a download versus deleting the original recording.

Follow an existing list's equivalent column headings and conventions. When terminology maintenance is in scope, update the applicable `WORD_LIST.md`; otherwise propose the entry with the copy. If no word list exists, create one only when establishing shared terminology is part of the task. A short list of real decisions is sufficient.

## Implement when requested

Treat historical UI examples as illustrations. Consult current official Apple documentation when a task depends on present-day component behavior, APIs, or platform requirements.

Follow the project's existing string storage, localization, capitalization, and accessibility conventions. On Apple platforms, inspect the relevant String Catalog, strings resources, or source call sites used by the project. Preserve interpolation arguments, plural behavior, and string identity unless the task requires changing them. Account for affected translations through the existing workflow; an English edit does not establish translation quality.

Check what the controls actually do before changing their labels. Update related visible and accessibility copy within the requested scope. Keep unrelated behavior changes out of a wording edit; surface a required interaction change explicitly.

Verify affected layouts and accessibility behavior when a running app or preview is available: larger text, long translations, reading order, and meaningful labels. Run relevant existing checks when the edits affect resources or behavior. If only source or screenshots are available, report the checks performed and the remaining runtime or language review, without claiming those checks passed.

## Deliver

- **Plan or draft:** Provide ready-to-use copy grouped by screen, state, and element, with essential placement or timing notes. Include alternatives only when a meaningful choice remains.
- **Review:** Prioritize issues by their effect on understanding, choices, and recovery. Give the location, current wording, proposed wording, and a concise reason. Separate behavior questions from copy fixes.
- **Naming:** Recommend a name with its contextual tradeoffs and show it in actual UI language. Treat market and translation suitability as unverified until checked.
- **Implementation:** Summarize changed copy, affected files, verification, and any unresolved behavior or localization question.

Finish when the requested elements and relevant states are covered, terminology agrees, and the copy accurately supports the intended next action. Scale the explanation to the task; a button rewrite does not need a full content strategy.
