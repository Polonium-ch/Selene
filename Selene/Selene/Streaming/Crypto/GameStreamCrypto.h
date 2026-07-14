#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// This device's persistent GameStream/Sunshine pairing identity: an RSA-2048
/// self-signed X.509 certificate + private key, generated once and persisted
/// to disk. Mirrors the legacy Qt client's `identitymanager.cpp` exactly
/// (same CN, key size, and 20-year validity) so the resulting cert/key would
/// be indistinguishable to a Sunshine host.
@interface GameStreamIdentity : NSObject

+ (instancetype)shared;

/// PEM-encoded self-signed X.509 certificate (CN="NVIDIA GameStream Client").
@property (nonatomic, readonly) NSString *certificatePEM;

/// Random 64-bit ID (lowercase hex), generated once and persisted. Sent as
/// this client's `uniqueid` in every GameStream HTTP request.
@property (nonatomic, readonly) NSString *uniqueId;

/// Signs `message` with this identity's private key (RSA-SHA256) - used in
/// the pairing challenge-response and `clientpairingsecret` stages.
- (NSData *)signSHA256:(NSData *)message;

/// Exports this identity as a PKCS#12 bundle (cert + private key), suitable
/// for importing as a `SecIdentity` for mTLS client authentication against a
/// paired Sunshine host.
- (nullable NSData *)pkcs12DataWithPassword:(NSString *)password;

@end

/// Stateless OpenSSL primitives used by the NVIDIA GameStream pairing
/// handshake (`nvpairingmanager.cpp`). Kept dependency-light (OpenSSL only,
/// no Qt) so it can live in this Qt-free SwiftUI target.
@interface GameStreamCrypto : NSObject

+ (NSData *)randomBytesOfLength:(NSUInteger)length;
+ (NSData *)sha1:(NSData *)data;
+ (NSData *)sha256:(NSData *)data;
+ (NSData *)aes128ECBEncrypt:(NSData *)plaintext key:(NSData *)key;
+ (NSData *)aes128ECBDecrypt:(NSData *)ciphertext key:(NSData *)key;

/// Extracts the raw ASN.1 signature bytes embedded in a PEM certificate
/// (its own self-signature) - used as part of the challenge data in pairing
/// stage 2, and to authenticate the server's identity in stage 3.
+ (nullable NSData *)signatureFromCertificatePEM:(NSString *)certificatePEM;

/// Verifies `signature` over `data` using the public key from
/// `certificatePEM` (RSA-SHA256) - used to confirm the pairing response
/// really came from the server we think we're pairing with (guards against
/// a PIN-guessing MITM).
+ (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data certificatePEM:(NSString *)certificatePEM;

@end

NS_ASSUME_NONNULL_END
