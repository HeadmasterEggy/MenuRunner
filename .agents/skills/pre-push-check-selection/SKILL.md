---
name: pre-push-check-selection
description: Picks the smallest set of checks for the paths a MenuRunner change touches and records the evidence against the git tree, not the branch name. Use before every push, after every rebase or merge of main, and before saying a check passed.
---

# Pre-push check selection

## Pick checks by path

List the changed paths with `git diff --name-only origin/main...HEAD`, then run every row that matches.

| Changed paths | Checks |
| --- | --- |
| anything | `scripts/guardrails/check-all.sh` (file length, no comments, banned APIs, skills, branch name) |
| `Sources/**` | compile on Joey's Mac with `swiftc -O -target arm64-apple-macos14.0` over all of `Sources`, in a temporary worktree |
| `Sources/Monitors/**`, `Sources/App/Sampler.swift` | run the test binary with `--stats`, and `--detail` for the page you changed; compare against Activity Monitor once |
| `Sources/Runners/**` | `--render` or `--preview` frames for the runner at low, mid and full load; `--bench` if the draw code got heavier |
| `Sources/Panel/**`, `Sources/Settings/**`, `Sources/AI/**` | screenshot the test binary with `--open-panel`, `--open-settings` or `--open-analysis`, in light and dark, in English and Chinese |
| `Sources/Update/**`, version in `build.sh` | `--check-update` and an install with `--pretend-version 1.0.0` on a copy under `/tmp`, never on `~/Applications` |
| `build.sh`, `make_dmg.sh` | read the diff line by line; both kill and reinstall the running app, so run them only when Joey expects it |
| `docs/**` | open `docs/index.html` in a browser in both languages and at phone width |
| `.agents/**`, `AGENTS.md` | `scripts/guardrails/check-skills.sh` |
| `scripts/guardrails/**` | break the rule on purpose once and confirm the check goes red with a message that says how to fix it |

Compile checks never use `./build.sh`: it kills and reinstalls Joey's running app. How to reach the Mac is in project memory under compile-check-on-mac.

## Record evidence against the tree

For each check write down:

```
tree=$(git rev-parse HEAD^{tree})  command  exit code  counts (files, warnings, frames)
```

- A rebase, a merge of main or any new commit changes the tree. Rerun the checks that the new paths touch.
- A later pass does not erase an earlier failure. Say what failed and what fixed it.
- A check that could not run is written as "not run" with the reason. Never write "passed" for it.
- Only one heavy job at a time on Joey's 16 GB Mac: a compile, a release build, Xcode or a long benchmark.
