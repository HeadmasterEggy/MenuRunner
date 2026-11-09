<div align="center">

<img src="docs/icon.png" width="128" alt="MenuRunner icon">

# MenuRunner

**A tiny macOS menu bar runner + Liquid Glass system monitor**

[![English](https://img.shields.io/badge/Language-English-0A84FF?style=for-the-badge)](README.md)
[![简体中文](https://img.shields.io/badge/语言-简体中文-E5484D?style=for-the-badge)](README.zh-CN.md)

[![Release](https://img.shields.io/github/v/release/HeadmasterEggy/MenuRunner?style=flat-square)](https://github.com/HeadmasterEggy/MenuRunner/releases/latest)
![macOS](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-555?style=flat-square)

<img src="docs/panel.png" width="260" alt="Panel">&nbsp;&nbsp;<img src="docs/cpu.png" width="260" alt="CPU details">&nbsp;&nbsp;<img src="docs/memory.png" width="260" alt="Memory usage by app">

<img src="docs/settings.png" width="260" alt="Settings">

<img src="docs/rocket.png" width="640" alt="Rocket Cat">

<img src="docs/runners.png" alt="Runners">

</div>

## Features

- **Runners** — a steaming coffee cup, a colour pixel-art Rocket Cat (an orange tabby riding a rocket with a flickering flame), a spinning fan, a scrolling heartbeat line, bouncing sound-wave bars, an hourglass that flips when the sand runs out, a colour lava lamp, a turning DNA double helix, a sweeping radar, a squash-and-stretch bouncing ball and a clock with spinning hands — all original designs, drawn in code; the monochrome ones are template images that adapt to light / dark menu bars. Their speed follows CPU, GPU or memory usage, in three clearly different levels: the fan spins faster with a longer trail, the bars jump higher, the steam thickens, the rocket flame grows, the heartbeat packs in more, taller beats, the sand pours faster, the lava blobs multiply, the helix gains rungs, the radar trail lengthens with more blips, the ball bounces higher and the clock hands blur.
- **Menu bar metrics with live mini graphs** — CPU, GPU, memory, battery, network, SoC or battery temperature, fan speed (on Macs with fans). Choose *Graph + Number*, *Graph only* or *Number only*.
- **Liquid Glass panel** (`NSPopover` + `NSGlassEffectView`), animated at 60 fps:
  - Machine spec — model, chip, CPU / GPU cores, memory, disk, macOS version
  - CPU (System / User / Idle) and GPU history charts
  - Memory breakdown (App / Wired / Compressed)
  - Storage ring, battery level, health, cycle count and estimated time left (or time until full)
  - Temperatures — SoC, battery, SSD, plus fan speed on Macs with fans
  - Network upload / download speed
  - **Click any card for details** (with smooth slide / fade transitions) — app disk usage largest-first, per-core CPU and top apps by CPU, GPU utilization and top apps by GPU, memory by app, every temperature sensor and each fan with its RPM range, all volumes, full battery info (capacity, voltage, power, adapter), network interfaces and top apps by traffic, full machine spec
- **Power usage** — a Power card shows whole-system watts and the apps drawing the most power right now; its detail page adds a 24-hour chart, the apps that used the most energy in the last 24 hours, and a link to AI analysis. MenuRunner records per-app energy and the other stats in 5-minute buckets for 14 days (turn it off under *Settings → Power*).
- **AI power analysis** — after it has been recording for a while, *AI Analysis* sends a summary of the recorded data to Claude (your Anthropic API key) or any OpenAI-compatible endpoint (OpenAI, DeepSeek, a local Ollama, …) and shows what drains power and what to change. Keys are stored only on this Mac, in a file readable just by your user account (`~/Library/Application Support/MenuRunner/ai-keys.json`).
- **Settings** — refresh rate (0.5 s / 1 s / 2 s), °C / °F, English / Simplified Chinese, launch at login, open Activity Monitor.
- **Updates** — *Check for Updates* looks at the latest GitHub Release and installs it in place; with *Automatically Update* on (the default) MenuRunner checks every 6 hours and updates itself, then relaunches.

## Install

1. Download `MenuRunner-x.y.dmg` from [Releases](https://github.com/HeadmasterEggy/MenuRunner/releases/latest).
2. Open the DMG and drag **MenuRunner** into **Applications**.
3. The app is not notarized, so macOS blocks it on first launch. Either:
   - open **System Settings → Privacy & Security** and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/MenuRunner.app`

Left-click the menu bar icon to open the panel; right-click it (or use the gear button) for settings.

## Build from source

Runs on macOS 14 Sonoma or later on Apple Silicon. Liquid Glass is used on macOS 26 and later; older versions get a translucent material look instead. Building needs the Xcode Command Line Tools.

```sh
./build.sh      # compile, ad-hoc sign, install to ~/Applications
./make_dmg.sh   # build dist/MenuRunner-<version>.dmg
```

To publish an update, bump `CFBundleShortVersionString` in `build.sh`, run `./make_dmg.sh`, and attach `dist/MenuRunner-<version>.dmg` to a GitHub Release tagged `v<version>`. Installed copies pick it up from there.

Regenerate the app icon (`assets/AppIcon.icns`):

```sh
MenuRunner.app/Contents/MacOS/MenuRunner --icon /tmp/AppIcon.iconset
iconutil -c icns /tmp/AppIcon.iconset -o assets/AppIcon.icns
```


Debug helpers:

```sh
MenuRunner.app/Contents/MacOS/MenuRunner --stats            # print all readings
MenuRunner.app/Contents/MacOS/MenuRunner --preview out.png  # export runner frames
```

## Notes

- SoC / SSD temperatures come from the system HID temperature sensors through a private IOKit API (the same approach Stats and iStat use). No root needed, but future macOS versions may change it; the panel shows `--` when unavailable.
- Fan speed is read from the SMC (`AppleSMC`), also without root. Macs without fans, like the MacBook Air, simply don't show the fan row or menu bar option.
- Per-app energy comes from the kernel's per-process energy counter (`proc_pid_rusage`, `ri_energy_nj`) and whole-system power from the SMC (`PSTR`) or battery telemetry. Per-app figures only count the energy of each process's own work on the chip, so they add up to less than the whole-system number, which includes the display.
- Everything else uses public APIs: `host_statistics`, IORegistry, `getifaddrs` and IOKit power sources.
