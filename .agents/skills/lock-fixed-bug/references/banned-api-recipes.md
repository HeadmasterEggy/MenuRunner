# Banned-API recipes

`scripts/guardrails/banned-apis.tsv` has one rule per line, four tab-separated columns:

| Column | Meaning |
| --- | --- |
| pattern | extended regex matched against every line of every tracked `Sources/**/*.swift` file |
| allowed | extended regex for the file paths that may still use it; `^$` means no file |
| message | what to use instead, written as an instruction |
| source | the PR that fixed the bug |

`scripts/guardrails/check-banned-apis.sh` prints each hit with its file and line, then the message.

## Writing a good rule

- Write the message as the fix: "Use MenuPanel", not "NSPopover is bad".
- Match the call, not a word that also appears in other names. `NSHost([^i]|$)` matches `NSHost` but not `NSHostingView`.
- Allow exactly the one wrapper file that is meant to call the raw API, for example the glass helpers in `Sources/Style/GlassBackground.swift` and `Sources/AI/GlassStyle.swift`.
- Grep the current tree before adding it: the rule must print nothing on main, or the PR must fix every hit.
- Prove it with `redgreen.sh 'scripts/guardrails/check-banned-apis.sh' <fixed-file>`.

## Examples

```
NSPopover	^$	Use MenuPanel (Sources/Panel/MenuPanel.swift).	PR #47
\.glassEffect\(	^Sources/AI/GlassStyle\.swift$	Use glassCard so macOS 14 still launches.	PR #45
```

## When a grep cannot express it

- Main-thread blocking calls hidden behind a helper: move the helper to a type whose name says it is slow, then ban the raw call outside it.
- Shared mutable caches read from two queues: put the cache behind a type that only exposes locked access, then ban direct use of the storage.
- Counters that can wrap: give them a 64-bit wrapper type and ban the 32-bit source.
