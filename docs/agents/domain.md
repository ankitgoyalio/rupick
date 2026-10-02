# Domain docs

## Layout

This repository uses a single-context layout:

- `GLOSSARY.md` at the repository root.
- ADRs under `docs/adr/`.

## Before exploring the codebase

Read the root glossary and ADRs relevant to the area being explored.
If these documents do not exist, proceed silently. The domain-modeling
skill creates them lazily when terms or decisions are resolved.

## Use the glossary's vocabulary

Use defined domain terms in issue titles, proposals, hypotheses, and
test names. Follow the glossary's preferred terms and avoided synonyms.

For an undefined concept, check whether the proposed term fits the
project. Record real vocabulary gaps for domain-modeling.

## Flag ADR conflicts

When a proposal contradicts an ADR, identify the decision and explain
why it should be reopened rather than silently overriding it.
