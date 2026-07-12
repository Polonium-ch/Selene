# Selene

Selene is a native macOS client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream game streaming, built on the [Moonlight](https://moonlight-stream.org) protocol stack.

It started as an independent fork of [moonlight-qt](https://github.com/moonlight-stream/moonlight-qt), stripped down to a macOS-only build. Selene doesn't track moonlight-qt's releases or follow its roadmap — it has its own pace and its own decisions, pulling in upstream changes only when they're worth it.

**Apple Silicon only.** This is a fully conscious decision, not an oversight, and it isn't going to change. Apple itself has been winding Intel Mac support down for years, so investing effort into supporting a platform on its way out doesn't make sense for a project starting fresh today. On top of that, there's no Intel Mac available to test against here, so any Intel compatibility claim would be untested and unreliable anyway. Intel support requests will be declined.

## Status

Selene is early and actively changing. Today it still runs the streaming engine largely as inherited from moonlight-qt (Qt/QML UI, FFmpeg decode pipeline, VideoToolbox/Metal rendering, the custom GIP controller bridge for Xbox-licensed USB pads). Two things are in progress:

- Replacing the Qt/QML interface with a genuinely native macOS UI.
- Migrating the underlying engine to Rust, piece by piece, keeping the existing C/C++/Objective-C++ code running underneath until each piece is ported.

Nothing here is stable yet. Expect things to move around.

## Features (inherited from the current engine)

- Hardware-accelerated video decoding via VideoToolbox and Vulkan (MoltenVK)
- H.264, HEVC, and AV1 codec support (AV1 requires Sunshine and a supported host GPU)
- YUV 4:4:4 and HDR streaming support (Sunshine only)
- 7.1 surround sound audio
- Gamepad support with force feedback and motion controls, including direct USB support for GIP-protocol (Xbox One/Series-licensed) controllers that macOS has no native driver for
- Support for both pointer capture (for games) and direct mouse control (for remote desktop)

## Building

macOS on Apple Silicon (arm64) only. Intel Macs are not supported and are not a build target.

### Requirements
- An Apple Silicon Mac
- Qt 6.7 SDK or later
- Xcode 14 or later
- [create-dmg](https://github.com/sindresorhus/create-dmg) (only if building a DMG for distribution)

### Setup
1. Install the Qt SDK from https://www.qt.io/download (or via Homebrew: `brew install qt`).
2. Fetch submodules and prebuilt dependencies:
   ```
   git submodule update --init --recursive
   python3 setup-deps.py
   ```
   Repeat this step whenever you pull new changes.
3. Build:
   ```
   qmake6 moonlight-qt.pro
   make release
   ```
   The built app bundle will be under `build/app/` (or `app/` if building in-place without a separate build directory).
4. To build a distributable DMG, run `scripts/generate-dmg.sh Release` from the repository root with Qt's `bin` folder in your `$PATH`.

## License

Selene is licensed under the [GNU General Public License v3.0](LICENSE), the same license as Moonlight.

## Acknowledgments

Selene builds on the protocol and streaming work of the [Moonlight](https://github.com/moonlight-stream) and [Sunshine](https://github.com/LizardByte/Sunshine) projects. Thanks to both communities for the groundwork.
