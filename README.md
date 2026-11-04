<div align="center">

# MenuRunner

**A tiny macOS menu bar runner + Liquid Glass system monitor**

[![English](https://img.shields.io/badge/Language-English-0A84FF?style=for-the-badge)](README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-E5484D?style=for-the-badge)](README.zh-CN.md)

[![Release](https://img.shields.io/github/v/release/HeadmasterEggy/MenuRunner?style=flat-square)](https://github.com/HeadmasterEggy/MenuRunner/releases/latest)
![macOS](https://img.shields.io/badge/macOS-26%2B-black?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-555?style=flat-square)

<img src="docs/panel.png" width="320" alt="Panel">&nbsp;&nbsp;<img src="docs/settings.png" width="210" alt="Settings">

<img src="docs/runners.png" alt="Runners">

</div>

## Features

- **Runners** — a galloping cat and a steaming coffee cup, drawn in code as template images that adapt to light / dark menu bars. Their speed follows CPU, GPU or memory usage.
- **Menu bar metrics with live mini graphs** — CPU, GPU, memory, battery, network, SoC or battery temperature. Choose *Graph + Number*, *Graph only* or *Number only*.
- **Liquid Glass panel** (`NSPopover` + `NSGlassEffectView`), animated at 60 fps:
  - Machine spec — model, chip, CPU / GPU cores, memory, disk, macOS version
  - CPU (System / User / Idle) and GPU history charts
  - Memory breakdown (App / Wired / Compressed)
  - Storage ring, battery level, health and cycle count
  - Temperatures — SoC, battery, SSD
  - Network upload / download speed
- **Settings** — refresh rate (0.5 s / 1 s / 2 s), °C / °F, English / 简体中文, launch at login, open Activity Monitor.

## Install

1. Download `MenuRunner-x.y.dmg` from [Releases](https://github.com/HeadmasterEggy/MenuRunner/releases/latest).
2. Open the DMG and drag **MenuRunner** into **Applications**.
3. The app is not notarized, so macOS blocks it on first launch. Either:
   - open **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/MenuRunner.app`

Left-click the menu bar icon to open the panel; right-click it (or use the gear button) for settings.

## Build from source

Requires macOS 26+ on Apple Silicon and the Xcode Command Line Tools.

```sh
./build.sh      # compile, ad-hoc sign, install to ~/Applications
./make_dmg.sh   # build dist/MenuRunner-<version>.dmg
```

Debug helpers:

```sh
MenuRunner.app/Contents/MacOS/MenuRunner --stats            # print all readings
MenuRunner.app/Contents/MacOS/MenuRunner --preview out.png  # export runner frames
```

## Notes

- SoC / SSD temperatures come from the system HID temperature sensors through a private IOKit API (the same approach Stats and iStat use). No root needed, but future macOS versions may change it; the panel shows `--` when unavailable.
- Everything else uses public APIs: `host_statistics`, IORegistry, `getifaddrs` and IOKit power sources.
