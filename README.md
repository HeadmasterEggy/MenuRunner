# MenuRunner

A tiny macOS menu bar app: an animated runner that speeds up with your CPU, plus a Liquid Glass system monitor panel.

一个 macOS 菜单栏小工具：菜单栏里有一个会跑的小角色，CPU 越忙跑得越快；点开是一块液态玻璃风格的系统监控面板。

<p>
  <img src="docs/panel.png" width="320" alt="Panel">
  <img src="docs/settings.png" width="210" alt="Settings">
</p>

![Runners](docs/runners.png)

## Features / 功能

- **Runners**: a galloping cat and a steaming coffee cup, drawn in code as template images (adapts to light/dark menu bar). Speed follows CPU, GPU or memory usage.
  **Runner**：奔跑的猫、冒热气的咖啡，代码绘制的模板图，自动适配深浅色菜单栏；速度可跟随 CPU / GPU / 内存。
- **Menu bar metrics** with live mini graphs: CPU, GPU, memory, battery, network, SoC / battery temperature.
  **菜单栏指标**带动态小图：CPU、GPU、内存、电池、网络、芯片 / 电池温度。
- **Liquid Glass panel** (`NSPopover` + `NSGlassEffectView`), animated at 60 fps:
  **液态玻璃面板**，60fps 动画：
  - Machine spec: model, chip, CPU/GPU cores, memory, disk, macOS version / 本机配置
  - CPU (System / User / Idle) and GPU history charts / CPU、GPU 历史曲线
  - Memory breakdown (App / Wired / Compressed) / 内存细分
  - Storage ring, battery level, health and cycle count / 存储环形图、电量、健康度、循环次数
  - Temperatures: SoC, battery, SSD / 温度：芯片、电池、SSD
  - Network upload / download speed / 网络上传下载速度
- Settings: refresh rate (0.5s / 1s / 2s), °C / °F, 中文 / English, launch at login, open Activity Monitor.
  设置：刷新频率、温度单位、中英文切换、开机自动启动、打开活动监视器。

## Requirements / 环境

- macOS 26 or later (Liquid Glass APIs), Apple Silicon
- Xcode Command Line Tools (`swiftc`)

## Build / 构建

```sh
./build.sh
```

This compiles `main.swift` into `MenuRunner.app`, signs it ad-hoc, and installs it to `~/Applications`.
Then open `~/Applications/MenuRunner.app`. Left-click the menu bar icon for the panel, right-click (or the gear button) for settings.

会编译出 `MenuRunner.app`，做本地签名并安装到 `~/Applications`。左键点菜单栏图标打开面板，右键（或面板里的齿轮）打开设置。

Debug helpers / 调试命令:

```sh
MenuRunner.app/Contents/MacOS/MenuRunner --stats            # print all readings
MenuRunner.app/Contents/MacOS/MenuRunner --preview out.png  # export runner frames
```

## Notes / 说明

- SoC / SSD temperatures are read from the system HID temperature sensors through a private IOKit API (the same approach Stats / iStat use). No root needed, but it may change in future macOS versions — the panel shows `--` if unavailable.
  芯片 / SSD 温度通过 IOKit 私有接口读取系统温度传感器，无需管理员权限，但未来 macOS 版本可能变化，读不到时显示 `--`。
- CPU / GPU / memory / battery / disk / network use public APIs (`host_statistics`, IORegistry, `getifaddrs`, IOKit power sources).
