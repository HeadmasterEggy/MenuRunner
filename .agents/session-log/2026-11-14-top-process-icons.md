# 2026-11-14 统一内存详情页两个列表的进程图标

## 目标

Joey 说“loop 别停”。中英文截图里，内存详情页同一个进程（如 com.apple.Virtualization）在“按应用汇总”显示齿轮图标，在“占内存最多的进程”显示空白文档图标。

## 改动

- “占内存最多的进程”只有 `.app` 路径才取应用图标，其他进程用和“按应用汇总”一样的齿轮占位图标；行仍可点击，在 Finder 中显示可执行文件（`Sources/Panel/PanelController.swift`，`drawTopProcs`）

## 分支与 PR

- `fix/top-process-icons`：[#61](https://github.com/HeadmasterEggy/MenuRunner/pull/61)，draft

## 决策

- 同一轮截图里其他问题没改：网络接口上下行相同是系统计数器按 1 KB 跳动，不是代码问题；GPU 标题百分比和利用率行来自不同时刻的采样；设置页滚动条常显来自系统“显示滚动条”设置；“最多的应用”卡片高度固定是为了避免面板高度随应用数跳动。

## 验证

- `scripts/guardrails/check-all.sh` 通过；Mac 编译和截图结果见 PR。

## 后续
