# MenuRunner

A macOS menu bar app in Swift: animated runners plus a system monitor panel. One developer, Joey, who usually writes in Chinese. Minimum macOS 14, built with `swiftc` from `build.sh`, no Xcode project.

`CLAUDE.md` is a symlink to this file and `.claude/skills` is a symlink to `.agents/skills`, so every agent tool reads the same rules.

## Code rules

Follow `.agents/skills/code-rules/SKILL.md` for every change: no code comments, every file at most 1000 lines, files organized into folders, branches named `<type>/<short-description>`.

## Skills

| Skill | Use when |
| --- | --- |
| `code-rules` | writing, editing or reviewing any file, creating a branch, committing |
| `pr-delivery-loop` | taking a change from a fresh branch to a merged PR |
| `pre-push-check-selection` | choosing which checks to run for the paths changed, and recording evidence |
| `lock-fixed-bug` | fixing a bug, so a check goes red on the old code |
| `defect-class-review` | reviewing a diff against the bug classes MenuRunner has shipped |
| `feature-wiring-trace` | adding a setting, metric or card, or chasing a stale or default value |
| `skill-hygiene` | editing skills or this file, and turning lessons into rules |

## Guardrails

- `scripts/guardrails/check-all.sh` runs every check; CI runs it on each PR and push to main.
- `git config core.hooksPath scripts/hooks` turns on the pre-push hook for a clone.
- A past bug that a grep can catch goes into `scripts/guardrails/banned-apis.tsv` with its PR number.

## Protected files

| Tier | Files | Rule |
| --- | --- | --- |
| Release contract | version in `build.sh`, `make_dmg.sh`, `Sources/Update/` | change only with a note in the PR on how tags, the DMG name and the in-app updater still match |
| Rules | `AGENTS.md`, `.agents/skills/code-rules/`, `scripts/guardrails/` | change only when Joey asks or a review he accepted calls for it |
| Generated | `MenuRunner.app/`, `dist/` | never edited or committed |

## Working with Joey's Mac

- Compile checks run on Joey's Mac in a temporary `git worktree`. Never run `./build.sh` or `./make_dmg.sh` as a check: both kill and reinstall the running app.
- The Mac has 16 GB of memory. Run one heavy job at a time: a compile, a release build, Xcode or a long benchmark.
- Steps that need Joey's yes (merging, releasing, deleting files on his Mac, killing apps) are asked once, in the first message that needs them, naming the exact action and target.
- For a settings or toggle change, ask in one question: where it appears, its default, and whether it ships on by default.

## Evidence

- Record checks against `git rev-parse HEAD^{tree}` with the command and exit code. Rerun after any rebase or merge of main.
- A check that did not run is reported as not run, never as passed.
- Every UI string must describe something the code really does, in both languages.

## Standing rules

When Joey states a rule for the future, add it here or to the matching skill in the same PR, and keep each project memory listed in the memory index.
