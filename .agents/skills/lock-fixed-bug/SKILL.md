---
name: lock-fixed-bug
description: Fixes a MenuRunner bug at its root and adds one machine check that is red on the old code and green on the fix, so the bug cannot come back. Use when fixing any bug, and when writing a new feature with many ways to break.
---

# Lock a fixed bug

## 1. Fix the root cause

- Reproduce first, then find the reason, not just the symptom. Write the reason in one sentence for the PR.
- Check whether the same mistake exists elsewhere: `grep -rn` for the call or pattern across `Sources`.

## 2. Pick the cheapest lock that would have caught it

From cheapest to most expensive:

1. A banned-API rule: one line in `scripts/guardrails/banned-apis.tsv`. See `references/banned-api-recipes.md`.
2. The type system: make the wrong call impossible, for example an enum parameter every caller must choose, a wrapper type for 64-bit counters, a function that takes a lock instead of a bare shared cache.
3. A new `scripts/guardrails/check-*.sh` for a fact that spans files, added to `check-all.sh`.
4. Delete the helper that invites the mistake and move callers to the safe one.
5. A `--verify` or `--stats` assertion in `Sources/Debug/DebugCommands.swift`, run on Joey's Mac.
6. A manual step in `.agents/skills/pre-push-check-selection/SKILL.md`.

If nothing can catch it (animation timing, model wording, a macOS bug), write one sentence in the PR on why.

## 3. Prove the lock fails on the old code

```sh
.agents/skills/lock-fixed-bug/scripts/redgreen.sh '<check command>' <fixed-file>...
```

It swaps the fixed files back to `origin/main`, runs the check (must fail), restores them, runs it again (must pass), and prints the tree hash. A check that passes on the old code does not expose the bug. Pass `-b <ref>` for another base.

- Paste the red output into the PR.
- A Swift check that needs a compile runs on Joey's Mac in a temporary worktree; never through `./build.sh`.

## 4. Write the source

Every banned-API rule and every new check carries its source: the PR number and what went wrong. Before deleting one, read the source and know why it was added.

## Failure list first

For a new subsystem that must be tested on its own (an updater step, a monitor reading a new sensor, a recorder writing files), list every way it can break in the PR description before writing the code, then make sure each one has a check or a sentence on why not. Prefer a run on the real app with a reviewable result (a `--stats` dump, a screenshot) over tests written after the code to match it.
