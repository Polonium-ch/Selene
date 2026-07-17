#import "GameStreamCrypto.h"

#include "selene_crypto.h"

// GameStreamIdentity/GameStreamCrypto's actual crypto logic lives in the
// Rust crate at Selene/RustCrypto (see selene_crypto.h) - this file is
// just the NSData/NSString <-> SeleneCryptoBuffer marshalling layer, kept
// as a thin ObjC++ shim so every existing Swift call site and this class's
// public API stay unchanged.

static NSString *const kIdentitySubdirectory = @"Selene";

static NSURL *SupportDirectoryURL(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = [fm URLForDirectory:NSApplicationSupportDirectory
                              inDomain:NSUserDomainMask
                     appropriateForURL:nil
                                create:YES
                                 error:nil];
    NSURL *dir = [base URLByAppendingPathComponent:kIdentitySubdirectory isDirectory:YES];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

// Consumes `buf` (always safe to call, even with a NULL ptr) and returns
// an NSData - empty (not nil) when `buf.ptr` is NULL, matching the
// contract every non-nullable method here relied on before this port.
static NSData *NSDataFromBuffer(SeleneCryptoBuffer buf)
{
    NSData *data = buf.ptr != NULL ? [NSData dataWithBytes:buf.ptr length:buf.len] : [NSData data];
    selene_crypto_free_buffer(buf);
    return data;
}

// Same as NSDataFromBuffer, but returns nil on a NULL ptr - for the two
// methods whose ObjC signature is explicitly `nullable`.
static NSData *_Nullable NSDataFromBufferNullable(SeleneCryptoBuffer buf)
{
    NSData *data = buf.ptr != NULL ? [NSData dataWithBytes:buf.ptr length:buf.len] : nil;
    selene_crypto_free_buffer(buf);
    return data;
}

static NSString *NSStringFromBuffer(SeleneCryptoBuffer buf)
{
    NSString *str = buf.ptr != NULL
        ? [[NSString alloc] initWithBytes:buf.ptr length:buf.len encoding:NSUTF8StringEncoding]
        : @"";
    selene_crypto_free_buffer(buf);
    return str;
}

@implementation GameStreamIdentity {
    SeleneIdentity *_handle;
}

+ (instancetype)shared
{
    static GameStreamIdentity *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[GameStreamIdentity alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        NSString *dir = SupportDirectoryURL().path;
        _handle = selene_identity_shared(dir.UTF8String);
    }
    return self;
}

- (NSString *)certificatePEM
{
    return NSStringFromBuffer(selene_identity_certificate_pem(_handle));
}

- (NSString *)uniqueId
{
    return NSStringFromBuffer(selene_identity_unique_id(_handle));
}

- (NSData *)signSHA256:(NSData *)message
{
    return NSDataFromBuffer(selene_identity_sign_sha256(_handle, (const uint8_t *)message.bytes, message.length));
}

- (nullable NSData *)pkcs12DataWithPassword:(NSString *)password
{
    return NSDataFromBufferNullable(selene_identity_pkcs12(_handle, password.UTF8String));
}

@end

@implementation GameStreamCrypto

+ (NSData *)randomBytesOfLength:(NSUInteger)length
{
    return NSDataFromBuffer(selene_crypto_random_bytes(length));
}

+ (NSData *)sha1:(NSData *)data
{
    return NSDataFromBuffer(selene_crypto_sha1((const uint8_t *)data.bytes, data.length));
}

+ (NSData *)sha256:(NSData *)data
{
    return NSDataFromBuffer(selene_crypto_sha256((const uint8_t *)data.bytes, data.length));
}

+ (NSData *)aes128ECBEncrypt:(NSData *)plaintext key:(NSData *)key
{
    return NSDataFromBuffer(selene_crypto_aes128_ecb_encrypt((const uint8_t *)plaintext.bytes, plaintext.length, (const uint8_t *)key.bytes));
}

+ (NSData *)aes128ECBDecrypt:(NSData *)ciphertext key:(NSData *)key
{
    return NSDataFromBuffer(selene_crypto_aes128_ecb_decrypt((const uint8_t *)ciphertext.bytes, ciphertext.length, (const uint8_t *)key.bytes));
}

+ (nullable NSData *)signatureFromCertificatePEM:(NSString *)certificatePEM
{
    return NSDataFromBufferNullable(selene_crypto_signature_from_certificate_pem(certificatePEM.UTF8String));
}

+ (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data certificatePEM:(NSString *)certificatePEM
{
    return selene_crypto_verify_signature((const uint8_t *)signature.bytes, signature.length,
                                           (const uint8_t *)data.bytes, data.length,
                                           certificatePEM.UTF8String);
}

@end
