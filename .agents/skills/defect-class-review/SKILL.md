---
name: defect-class-review
description: Reviews a MenuRunner diff against the classes of bugs this app has actually shipped, and grows that list after each new fix. Use when reviewing a PR or your own diff before pushing, and after merging a bug fix.
---

# Defect-class review

Go through the diff once per class below. For each class answer "not touched", "checked, fine" or "found: ...". Report only real findings, each with file, line and the input that breaks it.

## Classes from MenuRunner's own history

1. **Main thread blocked by a system call.** Name lookups, `sysctl` walks, process lists, file reads on the main thread. Fixed in PR #28 (`Host.current()` stalled the system detail page). Ask: what does this call do when the network or disk is slow?
2. **Shared state read from two queues.** The sampler queue and the main thread both touch caches. Fixed in PR #27 (temperature sensor cache rebuilt twice at once). Ask: who else reads or rebuilds this, and on which queue?
3. **Counter width and wrap.** 32-bit counters wrap; subtraction of a smaller new value goes negative or to zero. Fixed in PR #31 (network bytes wrapped every 4 GB). Ask: what is the type's max, and what happens on the sample after a reset or wrap?
4. **Child process or stream end not handled.** Readability handlers that keep firing on empty data, helpers never restarted. Fixed in PR #30 (`nettop` and `top` busy loop). Ask: what happens when the helper exits by itself?
5. **Failure path leaves the app worse off.** Partial update leaves the app closed or temp files behind. Fixed in PR #29 and PR #32. Ask: after each step fails, is the app still running and the disk clean?
6. **Data only refreshed while visible.** Values that update only when the panel is open. Fixed in PR #26 (stale tooltip temperature). Ask: who shows this value while the panel is closed?
7. **Racing animations and resizes.** A late completion handler undoes a newer state. Fixed in PR #51 (page switch versus panel open) and PR #46 (reopen during hide). Ask: if the user acts again mid-animation, which completion wins?
8. **Layout that does not follow content.** Rows that change while a card is open, scrollers covering cards. Fixed in PR #53 and PR #51. Ask: what happens with the longest app name, the most rows, Chinese text and the largest number?
9. **Timers that drift under load.** Frame counts advanced per tick slow down when ticks are late. Fixed in PR #54. Ask: is the animation driven by elapsed time?
10. **Settings state lost on switch.** Typed input dropped when another option changes. Fixed in PR #52 (API key lost on provider switch). Ask: what does every other field hold after this one changes?
11. **Platform API not available on the minimum macOS.** macOS 26 glass APIs crash or fail to link on macOS 14. Fixed in PR #45; locked by `scripts/guardrails/banned-apis.tsv`. Ask: is every new API gated, and was the compile done with `-target arm64-apple-macos14.0`?
12. **Status item UI that breaks the system menu bar.** An `NSPopover` on the status item kept the fullscreen menu bar visible. Fixed in PR #47; locked by `scripts/guardrails/banned-apis.tsv`.
13. **Ad-hoc signing side effects.** Keychain prompts after every rebuild, login items registered for test binaries. Fixed in PR #44. Ask: does this API depend on a stable code signature?
14. **Release contract broken.** Tag, version in `build.sh` and DMG name must match or the in-app updater stops finding releases. Ask: does this change the version, the asset name or `Sources/Update/`?
15. **UI text promises behavior the code does not do.** Every label, tooltip and setting description must match code that runs. Ask: where is the code that does what this string says, in both languages?

## Build the list further

After every merged bug fix:

1. Decide whether it fits an existing class. If so, add its PR number to that class.
2. If not, add a new class: a short name, the PR that fixed it, and the one question a reviewer should ask.
3. If the class can be caught by a machine, follow `.agents/skills/lock-fixed-bug/SKILL.md` and point to the lock here.
4. When a class has not appeared in 20 merged PRs and is machine-locked, shorten it to one line.

Keep this file under 300 lines; move long examples to `references/`.
