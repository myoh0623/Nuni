# Nuni

Nuni (눈이) is an independent, open-source macOS menu-bar app for controlling the brightness of built-in, USB-C, DisplayLink, virtual, and other connected displays.

Project home: [github.com/myoh0623/Nuni](https://github.com/myoh0623/Nuni) · Current version: **1.1.0**

The menu-bar eye mirrors the all-displays brightness level: it is fully open at 100%, gradually closes as brightness falls, and is closed at 0%.

## Download

Download the current universal build for Apple Silicon and Intel Macs:

[Download Nuni 1.1.0 for macOS](https://github.com/myoh0623/Nuni/releases/download/v1.1.0/Nuni-1.1.0-macos-universal.zip)

The downloadable build is ad-hoc signed and has not been Apple-notarized. If macOS blocks the first launch, Control-click Nuni, choose **Open**, and confirm once. GitHub Actions also produces a temporary build artifact for every change, while Releases is the permanent public download location.

## Features

- Manual, built-in-display sync, ambient sensor, solar-location, and clock modes
- A global brightness slider plus a separate draggable slider for every display
- Two-way synchronization between macOS brightness controls and the all-displays level in Manual and Sync modes
- Native system brightness control when macOS exposes it
- Public IOKit brightness control for compatible displays
- Reversible software gamma or a click-through shade for DisplayLink, virtual, and unsupported outputs
- Configurable minimum brightness to prevent an unusably dark screen
- Persistent per-display offsets that survive adaptive-mode changes
- Optional launch-at-login registration through the macOS login-item service

Nuni tries system-managed panel control first, followed by the public `IODisplaySetFloatParameter` API. It verifies readable hardware values after writes and reports when an IOKit result cannot be confirmed. Outputs that reject a readable hardware change, or expose no usable hardware brightness service, fall back to software gamma or a shade. The selected method is shown below each display.

## Build and run

Nuni requires macOS 13 or later and the command-line developer tools.

```sh
./build.sh
open build/Nuni.app
```

The script builds and ad-hoc signs a universal app for Apple Silicon and Intel Macs. Run the small logic test suite with:

```sh
./test.sh
```

Before publishing, run the complete formatting, Swift 6 concurrency, universal-build, code-signing, dependency-path, icon, and licence gate:

```sh
./verify.sh
```

Set `NUNI_LUX=123` before launching to test Sensor mode when an ambient-light value is not exposed by the Mac.

Nuni restores software gamma tables and removes its shades when it quits. Hardware brightness remains at the last value applied.

## Distribution notes

Native control of some Apple-managed panels uses dynamically loaded macOS `DisplayServices` and `CoreDisplay` symbols. Apple can change these private interfaces between macOS versions, and an app using them should not be expected to pass Mac App Store review. They are loaded from the operating system and are not redistributed by Nuni.

Before shipping a signed release, use a bundle identifier under a domain you control and follow the checklist in [PUBLISHING.md](PUBLISHING.md).

## Independence and license

Nuni is not affiliated with, endorsed by, or a release of Lunar. It contains no hidden Lunar Pro source, licence bypass, payment code, signing secret, or bundled `ddcctl` executable.

Nuni is released under the MIT License. The original Lunar MIT notice is retained for attribution in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSES/Lunar-MIT.txt](LICENSES/Lunar-MIT.txt).
