---
name: feature-wiring-trace
description: Traces one value from where MenuRunner produces it to every place that shows or uses it, layer by layer, so no wrapper or copy drops it on the way. Use when adding or changing a setting, a metric, a card, or an AI report field, and when a value shows up stale, empty or default.
---

# Feature wiring trace

Write the trace as a table in the PR. One row per hop, with the file, the name the value has there, and how you confirmed it arrives (a `--stats` dump, a screenshot, a log line).

## The usual hops in MenuRunner

| Hop | Where |
| --- | --- |
| Producer | a reader in `Sources/Monitors/` or `Sources/Power/`, or a control in `Sources/Settings/` |
| Stored setting | `UserDefaults` key; check the default when the key is missing |
| Sampling | `Sources/App/Sampler.swift`: is it sampled at all, how often, and also while the panel is closed |
| Model | `Sources/Panel/StatsModel.swift` or the AI model in `Sources/AI/AnalysisModel.swift` |
| Menu bar | `Sources/App/AppDelegate.swift` and `Sources/App/StatusVisibility.swift` for the status item text, graph and tooltip |
| Panel | the card in `Sources/Panel/` and its detail page from `Sources/Monitors/DetailProvider.swift` |
| AI report | `Sources/Power/PowerReport.swift` if the value should reach the analysis |
| Strings | every `L("中文", "English")` the value appears in, both languages |
| Outside the app | README in both languages and the landing page in `docs/`, if the feature is user-facing |

## Questions at every hop

- Does this layer copy the value into a new struct, and does that struct have the new field?
- Does a wrapper, cache or `prefix(n)` cut it?
- Is the unit the same as the layer before (bytes or MB, °C or °F, fraction or percent)?
- What does this layer show when the value is missing, zero or not supported on this Mac (no fan, no battery)?
- Does a setting change reach a running sampler, or only take effect after relaunch?

## Done when

Every hop has a row, and the last hop shows the real value on the test binary, not the default.
