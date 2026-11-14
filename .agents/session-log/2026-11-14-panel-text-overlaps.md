# 2026-11-14 修正面板里文字和图形重叠

## 目标

Joey 说“loop 别停”，继续找 bug。这一轮在 Joey 的 Mac 上把每个页面用中文和英文各截一遍图，这个 PR 修截图里看到的文字和图形重叠。

## 改动

- 功耗详情页 24 小时柱状图：柱子顶部留出“峰值”标签的高度，最高的柱子不再压住标签（`Sources/Panel/PowerCards.swift`，`drawSummary`）
- 主页功耗卡片：应用名和功耗数字之间留 6 pt 间距，不再连成“MRVisTest1.0 W”（`drawMain`）
- 网络卡片（宽卡和小卡）：曲线只用图表下方 70% 高度，峰值尖刺不再穿过“峰值”标签（`Draw.labelHeadroom`）
- 主页内存卡片：图例按实际文字宽度排开，英文“Compressed 4.9 GB”不再超出右边（`Draw.legend`）
- 温度详情页风扇卡片：每个风扇一行从 38 pt 加到 46 pt，转速范围不再贴着下一个风扇的名字

## 分支与 PR

- `fix/panel-text-overlaps`：见 README 表格

## 决策

- 这些是绘图位置问题，grep 抓不到，没加 guardrail；靠 Mac 上中英文截图验证。
- 风扇条按“占最高转速的比例”填充是原设计，没改成从最低转速算。

## 验证

- `scripts/guardrails/check-all.sh` 通过；Mac 编译和截图结果见 PR。

## 后续

- 网络详情页每个接口的上传和下载数值相同，需要在 Mac 上读计数器确认原因。
