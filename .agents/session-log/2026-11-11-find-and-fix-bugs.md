# 2026-11-11 找 bug 并修复

## 目标

Joey 让在当前 main 上再找找 bug，重点看最近合并的面板窗口、图表颜色、面板尺寸滚动和卡片拖动，再看其余代码；确认的 bug 用小 PR 修。之后 Joey 同意按建议处理“单独一行的小卡片”问题。

## 改动

- AI：切换 AI 服务商时先保存输入框里的 key，再加载新服务商的 key（`Sources/AI/AnalysisModel.swift`）
- 面板详情页：电池、系统、温度、存储、网络详情页在行数变化时重建，避免新行画到卡片外被裁掉（`Sources/Panel/PanelController.swift`，`detailPage(_:)`、`refitDetail()`）
- 面板主页：卡片宽高按每张卡自己的大小设置，单独一行的小卡片保持半宽（`Sources/Panel/PanelController.swift`，`makeMainPage`、`mainFrames`、`rowHeight`）

## 分支与 PR

- `fix/keep-ai-key-on-provider-switch`：[#52](https://github.com/HeadmasterEggy/MenuRunner/pull/52)，已合并
- `fix/detail-card-row-overflow`：[#53](https://github.com/HeadmasterEggy/MenuRunner/pull/53)，已合并
- `fix/keep-lone-small-card-half-width`：[#58](https://github.com/HeadmasterEggy/MenuRunner/pull/58)，draft

## 决策

- 单独一行的小卡片：原来自动铺满整行，但右键菜单仍显示“放大为宽卡片”，设置里也显示“小”，点了没有可见变化。选了“保持半宽”，让显示和用户的选择一致；放弃了“只改菜单文字”，因为那样设置和面板还是不一致。代价是隐藏一张成对的小卡片后，另一张旁边会留空。
- 详情页行数变化时不做滑动动画，直接替换页面，面板高度照常动画。
- 读过但没改：卡片拖动、`MenuPanel` 尺寸与滚动、图表颜色、更新器、功耗记录，没发现确定的 bug。AI 分析“取消后立刻重新分析”有理论上的竞态，窗口只有几毫秒，没改。

## 验证

- #52、#53：Joey 的 Mac 上在临时 worktree 里 `swiftc -O Sources/**/*.swift` 编译通过。
- #58：`scripts/guardrails/check-all.sh` 通过；Mac 编译和截图见 PR。

## 后续

- 无
