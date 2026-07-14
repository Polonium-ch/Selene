import Foundation

/// Client-generated parameters for one streaming session: a fresh AES
/// key/IV for the GameStream "remote input" encryption scheme, plus basic
/// video parameters. Built once per launch attempt and used both for the
/// `/launch` HTTP request (`GameStreamClient.launchApp`) and for the
/// `STREAM_CONFIGURATION` passed to `LiStartConnection` - mirrors
/// `Session::startConnectionAsync` in the legacy Qt client
/// (`app/streaming/session.cpp:626-694`).
struct StreamSessionConfig {
    let width: Int32
    let height: Int32
    let fps: Int32
    let bitrateKbps: Int32
    let remoteInputAesKey: Data // 16 bytes
    let remoteInputAesIv: Data // 16 bytes - only the first 4 are randomized, rest are zero (matches session.cpp)

    static func make(width: Int32 = 1920, height: Int32 = 1080, fps: Int32 = 60, bitrateKbps: Int32 = 20000) -> StreamSessionConfig {
        let key = GameStreamCrypto.randomBytes(ofLength: 16)
        var iv = GameStreamCrypto.randomBytes(ofLength: 4)
        iv.append(Data(repeating: 0, count: 12))
        return StreamSessionConfig(width: width, height: height, fps: fps, bitrateKbps: bitrateKbps, remoteInputAesKey: key, remoteInputAesIv: iv)
    }

    /// The `rikeyid` query parameter for `/launch` - the IV's first 4 bytes
    /// read as a big-endian integer (matches `nvhttp.cpp`'s
    /// `memcpy` + `qFromBigEndian` on the same bytes).
    var rikeyId: Int32 {
        remoteInputAesIv.withUnsafeBytes { raw in
            Int32(bigEndian: raw.load(fromByteOffset: 0, as: Int32.self))
        }
    }
}
