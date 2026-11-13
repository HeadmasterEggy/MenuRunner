---
name: skill-hygiene
description: Keeps MenuRunner's agent skills and rules accurate, linted and short, and turns accepted lessons into a skill line, a check or a memory the same day. Use when adding or editing a skill or AGENTS.md, when a review trigger below is reached, and after a retro.
---

# Skill hygiene

## Format, checked by CI

`scripts/guardrails/check-skills.sh` checks every `.agents/skills/*/SKILL.md`:

- frontmatter starts the file, `name` matches the folder;
- `description` is one line that says what the skill does and "Use when ...";
- the file is at most 500 lines; move detail into `references/`;
- every backticked repo path it mentions exists;
- `AGENTS.md` lists the skill.

## Review by activity, not by calendar

Reread the skills, `AGENTS.md` and `scripts/guardrails/banned-apis.tsv` when any of these is reached since the last review:

- 8 merged PRs;
- 5 bug fixes;
- 1 change to the folder layout in `Sources/`, to `build.sh`, or to the release flow;
- 1 time an agent broke a rule a skill already states.

In the review, delete what no longer applies, merge what repeats, and fix paths that moved. Write the date and the PR range reviewed in the PR description.

## Every rule has a source

A rule that came from an incident says where: the PR number, the date and what went wrong, in one line. Before deleting a rule, read its source.

## Lessons land the same day

Every point accepted in a retro or a review becomes, the same day, one of:

1. a line in a skill;
2. a check in `scripts/guardrails/`;
3. a project memory, listed in the memory index.

A lesson that is only written in a chat is lost.

## Standing rules

When Joey says something should always happen ("以后都……"), put it in `AGENTS.md` or the matching skill in the same PR, and tell any running thread it affects.
