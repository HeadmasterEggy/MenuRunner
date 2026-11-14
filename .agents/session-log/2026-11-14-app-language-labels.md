# 2026-11-14 修正面板和 AI 分析里没跟随 App 语言的文字

## 目标

Joey 说“loop 别停”，继续找 bug。这一轮在 Joey 的 Mac 上把每个页面用中文和英文各截一遍图，这个 PR 修其中“App 设成中文，部分文字还是英文”的问题。

## 改动

- 主页 CPU 卡片图例“System / User / Idle”加上中文（`Sources/Panel/PanelController.swift`，`drawCPU`）
- GPU 详情页“Tiler”加上中文“分块器”（`drawGPUStats`）
- AI 分析窗口和设置页的 SwiftUI 视图设置 `Lang.locale`，图表日期轴跟随 App 语言（`Sources/AI/AnalysisPanel.swift`、`Sources/Panel/PanelController.swift`）
- 用 `.formatted(date:time:)` 的地方改为带 `Lang.locale` 的 `Date.FormatStyle`：上次分析时间、发现的时间段、图表提示、设置里的“上次检查”（`Sources/AI/`、`Sources/Update/Updater.swift`）
- 功耗图表 y 轴的 0 显示为“0 W”，不再是“0.00 W”（`Sources/AI/AnalysisCharts.swift`）
- 电池卡片英文“On AC power”改成和标题一致的“On AC Power”（`Sources/Monitors/SystemInfo.swift`）
- `banned-apis.tsv` 加一条：禁止 `.formatted(date:`，它用系统语言而不是 App 语言

## 分支与 PR

- `fix/app-language-labels`：见 README 表格

## 决策

- `Updater.swift` 属于发布契约文件，这里只改了“上次检查”的日期显示，不碰版本号、标签和 DMG 名。
- 风扇条从 0 而不是从最低转速填充，是“占最高转速的百分比”的设计，没改。

## 验证

- `scripts/guardrails/check-all.sh` 通过；Mac 编译和截图结果见 PR。

## 后续

- 同一轮截图发现的面板文字重叠和网络接口上下行数值相同，另开 PR。
