---
name: code-rules
description: MenuRunner code rules. Use before writing, editing, splitting or reviewing any source file in this repo, and before every commit.
---

# MenuRunner code rules

代码不要加注释，每个文件不超过 1k 行代码，文件要归类好。

## 1. No code comments

- Do not write comments in source files: no `//`, `///`, `/* */`, no `#` comments in shell scripts, no `MARK:` lines.
- When editing a file that already has comments, remove the ones in the code you touch.
- Make code explain itself through names: clear type, function and variable names, small functions, named constants instead of magic numbers.
- Explanations belong in the PR description, the commit message or the README, never in the code.

## 2. Every file at most 1000 lines

- No source file may exceed 1000 lines. Aim well below that; around 300 to 600 lines is a healthy size.
- When a change would push a file over the limit, split it first, by responsibility, not by cutting it at an arbitrary line.
- Check before committing:

```sh
find . -path ./.git -prune -o -type f \( -name '*.swift' -o -name '*.sh' \) -print0 | xargs -0 wc -l | sort -n | awk '$2 != "total" && $1 > 1000'
```

The command must print nothing.

## 3. Organize files into folders

- Group files by area, one concern per file. For this app, folders like these fit:
  - `Sources/App/` for the entry point, app delegate and menu bar wiring
  - `Sources/Runners/` for the animated menu bar runners, one runner per file
  - `Sources/Monitors/` for CPU, memory and other system readers
  - `Sources/Panel/` for the popover panel views
  - `Sources/Settings/` for preferences and the settings window
  - `Sources/Support/` for shared helpers and extensions
- Name each file after the main type it holds, for example `CatRunner.swift`.
- Keep scripts, assets and docs in their own places (`scripts/` or the repo root for build scripts, `assets/`, `docs/`).
- When adding or moving Swift files, make sure `build.sh` compiles all of them, for example with `swiftc -O $(find Sources -name '*.swift') -o ...`.

## Before every commit

1. No new comments in the diff: `git diff --cached | grep -nE '^\+.*(//|/\*)'` should only show URLs or string contents.
2. The line-count check above prints nothing.
3. New files sit in the folder that matches their area.
4. `./build.sh` still builds.
