---
name: code-rules
description: MenuRunner code and branch rules. Use before writing, editing, splitting or reviewing any source file in this repo, before creating a branch, and before every commit.
---

# MenuRunner code rules

代码不要加注释，每个文件不超过 1k 行代码，文件要归类好。

## 1. No code comments

- Do not write comments in source files: no `//`, `///`, `/* */`, no `#` comments in shell scripts or workflow files, no `<!-- -->` in HTML, no `MARK:` lines. `scripts/guardrails/check-no-comments.sh` checks every tracked file.
- When editing a file that already has comments, remove the ones in the code you touch.
- Make code explain itself through names: clear type, function and variable names, small functions, named constants instead of magic numbers.
- Explanations belong in the PR description, the commit message or the README, never in the code.

## 2. Every file at most 1000 lines

- No source file may exceed 1000 lines. Aim well below that; around 300 to 600 lines is a healthy size.
- When a change would push a file over the limit, split it first, by responsibility, not by cutting it at an arbitrary line.
- Check before committing with `scripts/guardrails/check-file-length.sh`. It covers Swift, shell, web and workflow files.

## 3. Organize files into folders

- Group files by area, one concern per file. The current layout:
  - `Sources/main.swift` is the entry point
  - `Sources/App/` for the app delegate, sampling loop and localization
  - `Sources/Runners/` for the animated menu bar runners, one runner per file, with the shared `Runner.swift`
  - `Sources/Monitors/` for CPU, GPU, memory, network, battery, temperature and other system readers
  - `Sources/Panel/` for the popover panel, its cards, drawing helpers and stats model
  - `Sources/Settings/` for the settings window
  - `Sources/Update/` for checking GitHub Releases and installing updates
  - `Sources/Power/` for recording power history and building the report sent to AI
  - `Sources/AI/` for the AI provider client, API key storage and the analysis window
  - `Sources/Style/` for shared AppKit styling such as the macOS 14 safe glass helpers
  - `Sources/Debug/` for debug and command line helpers
  - `scripts/guardrails/` for the checks run by the pre-push hook and CI, `scripts/hooks/` for git hooks
- Put a new file in the folder that matches its area, and add a new folder only when a new area appears.
- Name each file after the main type it holds, for example `RocketCat.swift`.
- Keep build scripts at the repo root, check scripts in `scripts/`, images in `assets/`, screenshots and docs in `docs/`, agent skills in `.agents/skills/`, agent session logs in `.agents/session-log/`.
- `build.sh` compiles `Sources/**/*.swift`, so new Swift files must live under `Sources/`.

## 4. Branch names

- Format: `<type>/<short-description>`, all lowercase, words joined with hyphens, at most about five words.
- Types:
  - `feat/` for a new feature, for example `feat/lava-lamp-runner`
  - `fix/` for a bug fix, for example `fix/cpu-spike-on-wake`
  - `refactor/` for restructuring without behavior change, for example `refactor/split-panel-controller`
  - `docs/` for README, screenshots and other docs, for example `docs/update-zh-readme`
  - `chore/` for build scripts, config, skills and tooling, for example `chore/branch-naming-rule`
- Describe the change, not the person, the tool or the date. No issue numbers alone, no `wip`, `test` or `tmp` branches, and no AI tool names such as `claude/...` even when a tool picks the name.
- `scripts/guardrails/check-branch-name.sh` checks the current branch.
- One branch per change. Start it from the latest `main`.

## Before every commit

1. `scripts/guardrails/check-all.sh` passes: file length, no comments, banned APIs, skill format and branch name. Run `git config core.hooksPath scripts/hooks` once per clone so the pre-push hook runs it too.
2. New files sit in the folder that matches their area.
3. Swift changes compile against macOS 14 with `swiftc -target arm64-apple-macos14.0` over all of `Sources`, in a temporary worktree. Never use `./build.sh` as a check: it kills and reinstalls the running app.
4. The session log for this change is written in `.agents/session-log/`, following `.agents/skills/session-log/SKILL.md`.
