# Security Policy

## Supported Versions

Only the latest release is supported. Selene is a solo, actively developed project with no LTS branch - please update to the latest version before reporting anything.

## Reporting a Vulnerability

Please do not open a public issue for security vulnerabilities. Instead, use GitHub's private reporting: **Security** tab → **Report a vulnerability** on this repo.

This mainly applies to things like:

- Bypassing or forging NVIDIA GameStream / Sunshine PIN pairing
- Weaknesses in the mutual-TLS identity handling (`GameStreamMutualTLS`, `PairingStore`, Keychain-backed identities) or the OpenSSL-based RSA identity generation
- Anything that lets a session be intercepted, tampered with, or impersonated

Regular bugs, crashes, or streaming/input issues that aren't security-relevant should go through a normal [issue](.github/ISSUE_TEMPLATE) instead.

## A note on Gatekeeper warnings

Selene is **ad-hoc signed** - there's no paid Apple Developer ID behind this project (yet), so builds aren't notarized. Seeing macOS flag the app as "from an unidentified developer" after a manual `.dmg` install is expected and is not, by itself, a vulnerability - it means Apple hasn't reviewed the binary, not that anything is wrong with it.

- The [install script](install.sh) downloads the release and clears the quarantine flag for you automatically.
- Installing the `.dmg` manually requires clearing it yourself (`xattr -cr /Applications/Selene.app`), as noted in the [README](README.md#-installation).
- Since builds aren't notarized, only install Selene from the official [GitHub Releases](https://github.com/Polonium-ch/Selene/releases) page or the install script pointed at `install.getselene.ch` - be wary of any other source claiming to distribute it.
