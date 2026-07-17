# Changelog

All notable changes to Selene are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with categories kept simple: **New**, **Changed**, **Fixed**.

This file is the single source of truth for release notes: `scripts/release.sh` promotes `[Unreleased]` into a dated version section when cutting a release, and `scripts/update-appcast.sh` reads that section straight into the Sparkle update feed - so what's written here is what users see in the in-app updater.

## [Unreleased]

## [0.1.5] - 2026-07-17

### New

- "Unpair" option in a host's context menu

### Changed

- Pairing status now reconciles with what the host itself reports (`/serverinfo`'s `PairStatus`), so a host unpaired from Sunshine's own UI no longer shows as paired here
- Cryptography (identity generation/persistence, AES, SHA, RSA-SHA256 signing) now runs through a Rust crate on top of OpenSSL, replacing the previous Objective-C++ implementation - no behavior change for existing pairings

## [0.1.4] - 2026-07-16

### New

- Native Settings window - resolution, frame rate, bitrate, audio channels, HTTPS port, and packet size
- Native About window

### Changed

- Connecting screen now shows a blurred box-art backdrop instead of flat black

## [0.1.3] - 2026-07-16

### New

- Gamepad support - buttons, sticks, and analog triggers for any controller macOS pairs natively (DualSense, DualShock 4, Xbox, and other GameController-recognized pads)

### Changed

- Install script now points at `install.getselene.ch`

## [0.1.2] - 2026-07-15

### Fixed

- Sparkle update signing in CI

## [0.1.1] - 2026-07-15

### Fixed

- Homebrew dependency versions pinned for CI builds

## [0.1.0] - 2026-07-15

### New

- Initial native SwiftUI rewrite of the Moonlight/Sunshine client
- Bonjour and manual host discovery
- NVIDIA GameStream / Sunshine PIN pairing
- Hardware H.264 decoding (VideoToolbox) and native Opus audio (AudioToolbox)
- Keyboard and mouse input forwarding
- Session background / resume support
- In-app auto-updates via Sparkle
