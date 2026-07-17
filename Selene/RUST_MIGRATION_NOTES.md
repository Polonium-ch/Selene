# Rust migration notes

Internal tracking doc, not user-facing. Current phase: get the native SwiftUI
client fully functional with C/C++ for anything that isn't UI. Once it works
end-to-end, these are the pieces planned to move to Rust, in roughly the
order it makes sense to tackle them.

## Done

- **`GameStreamCrypto.h`/`.mm` -> `Selene/RustCrypto`** (2026-07-16, branch
  `rust/game-stream-crypto`): RSA-2048 identity generation/persistence,
  AES-128-ECB, SHA-1/256, RSA-SHA256 sign/verify all moved to a Rust crate
  using the `openssl` crate (kept on real OpenSSL rather than pure-Rust PKI
  crates specifically to preserve exact PEM/PKCS#12 byte-for-byte
  compatibility with already-persisted identities and macOS's Security
  framework import requirements). `GameStreamCrypto.h`/the Swift call sites
  are untouched - the ObjC++ `.mm` is now a thin buffer-marshalling shim
  over a C FFI boundary (`Selene/RustCrypto/include/selene_crypto.h`).
  Verified end-to-end against a real Sunshine host: fresh pairing, mTLS
  connect, and an already-persisted identity loading unchanged.

## Candidates to port to Rust

- **`GameStreamPairing.swift`** - the 5-stage NVIDIA GameStream pairing
  handshake (HTTP orchestration, XML parsing, protocol state machine).
  Currently Swift + `URLSession`. Good Rust candidate (`reqwest`/`hyper` +
  an XML crate) once the crypto core above has moved.
- **`GameStreamClient.swift`** - `/applist` + `/appasset` fetch/parse,
  `/launch`+`/resume`+`/cancel` (session lifecycle) over mTLS. Same category
  as pairing - networking + XML, no UI.
- **`SunshineServerInfo.swift`** - `/serverinfo` fetch/parse. Same category.
- **`StreamSessionConfig.swift`** - trivial value struct (AES key/iv +
  video params), moves for free alongside whichever of the above owns it.
- **`moonlight-common-c` itself** (vendored C sources under `src/`, `enet/`,
  `nanors/`) - this is the real GameStream protocol engine (RTSP/ENet/RTP).
  Not "ported to Rust" so much as **replaced** by a Rust reimplementation or
  a `moonlight-common-rs`-style crate if one ever exists; until then this
  C library stays exactly as-is regardless of what else moves, since it's
  already dependency-light (OpenSSL only) and proven working. Lowest
  priority / highest risk of the whole list - don't touch this without a
  concrete reason.
- **`GameStreamSession.h`/`.mm`** - the `LiStartConnection` bridge/callback
  glue. If moonlight-common-c itself never moves to Rust, this ObjC++ glue
  necessarily stays too (it's the thing calling it). Only relevant to
  revisit if the C engine above is ever actually replaced.
- **`StreamConnectionController.swift`** - thin `@Observable` wrapper
  surfacing `GameStreamSession`'s callbacks to SwiftUI. Same fate as
  `GameStreamSession` above - moves only if/when the underlying engine does.

## Likely stays native (not Rust), even long-term

- **`GameStreamMutualTLS.swift`** - builds the mTLS `URLSession` via a
  `SecIdentity` imported from Keychain. This is inherently a macOS
  Security-framework concern (Keychain access, `SecPKCS12Import`,
  `SecTrust`) - Rust has no native access to this without its own
  Objective-C/Swift bridge, so this glue layer probably stays put regardless
  of what the actual HTTP client is implemented in.
- **`PairingStore.swift`** - trivial `UserDefaults` persistence, not worth
  moving.
- Everything SwiftUI-facing (`ContentView`, `DevicesView`, `DeviceCardView`,
  `AppGridView`, `PairingSheetView`, `StreamWindowView`) - UI stays Swift per
  the project's stated direction.
- **`HostDiscoveryService.swift`** (Bonjour/`NWBrowser`) - platform-native
  discovery API, arguably fine to leave in Swift even though it's not
  strictly "UI" - revisit this call once the rest of the migration is done,
  it's low priority either way.

## Why not Rust from day one here

`nvhttp.cpp`/`nvpairingmanager.cpp` in the legacy Qt client are deeply
Qt-coupled (`QNetworkAccessManager`, `QXmlStreamReader`, `QString`,
`QSslCertificate`), so bridging them verbatim into this Qt-free SwiftUI app
would mean dragging in all of Qt just for pairing - defeating the point of
the native shell. The split adopted instead: crypto-critical primitives in
portable C/C++ (OpenSSL, no Qt) now, networking orchestration in Swift for
now, both intended to end up in Rust once the app is fully functional.
