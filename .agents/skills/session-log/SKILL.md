---
name: session-log
description: MenuRunner session log rule. Use at the start of every agent session to read recent logs, and before the last commit of any session that changes the repo to write its log in .agents/session-log/.
---

# MenuRunner session logs

每个 agent session 都要写 session-log，记录这次做了什么、为什么这么做、还剩什么。

## When

- Every session that changes the repo writes exactly one log, committed on the same branch and in the same PR as the change.
- A session that only answers questions or reads code and changes nothing does not need a log.
- If a later session continues the same branch or PR, update that log instead of creating a new one, and add a `## 进展` section with one dated line per later session.

## Before starting work

1. Read `.agents/session-log/README.md`.
2. Read the newest two or three logs, plus any log whose topic matches the task, so earlier decisions and open follow-ups are not lost.

## File name and place

- Path: `.agents/session-log/YYYY-MM-DD-<short-topic>.md`
- The date is the day the session started, in UTC.
- `<short-topic>` is lowercase kebab-case, at most about five words, and usually matches the branch description, for example `2026-11-12-runner-full-cpu-speed.md` for `fix/runner-full-cpu-speed`.
- If two sessions on the same day pick the same topic, add `-2` to the second.

## Content

Copy `.agents/session-log/TEMPLATE.md` and fill in every section. Write in Chinese; keep code identifiers, file paths, commands and PR titles as they are.

- `目标`: what the user asked for, in one or two sentences, and how the request was read if it was ambiguous.
- `改动`: what changed, grouped by area, with the main files or folders.
- `分支与 PR`: branch name, PR number and link, and its state when the session ended.
- `决策`: choices made and why, including options that were rejected. This is the most useful part for the next session.
- `验证`: how the change was checked, for example a compile on the Mac, screenshots or manual steps, and anything that was not checked.
- `后续`: open follow-ups, known issues, and what the next session should pick up. Write `无` if there is nothing.

## Rules

- Keep a log short: usually 30 to 120 lines, never over 1000.
- Never write API keys, tokens, passwords, email addresses or other personal data into a log.
- Describe what happened, not the conversation: no pasted chat transcripts or long tool output.
- Link PRs as `[#55](https://github.com/HeadmasterEggy/MenuRunner/pull/55)`.
- Add a row for the new log at the top of the table in `.agents/session-log/README.md`, newest first.
- Commit the log together with the change, or as the last commit on the branch before the PR is marked ready.
