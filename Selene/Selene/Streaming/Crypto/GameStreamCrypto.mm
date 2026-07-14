#import "GameStreamCrypto.h"

#include <openssl/asn1.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/pkcs12.h>
#include <openssl/rand.h>
#include <openssl/x509.h>

static NSString *const kCertFileName = @"identity_cert.pem";
static NSString *const kKeyFileName = @"identity_key.pem";
static NSString *const kUniqueIdFileName = @"identity_uniqueid.txt";

static NSURL *SupportDirectoryURL(void)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *base = [fm URLForDirectory:NSApplicationSupportDirectory
                              inDomain:NSUserDomainMask
                     appropriateForURL:nil
                                create:YES
                                 error:nil];
    NSURL *dir = [base URLByAppendingPathComponent:@"Selene" isDirectory:YES];
    [fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

@implementation GameStreamIdentity {
    NSString *_certificatePEM;
    NSString *_privateKeyPEM;
    NSString *_uniqueId;
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
        [self loadOrCreateCredentials];
    }
    return self;
}

- (void)loadOrCreateCredentials
{
    NSURL *dir = SupportDirectoryURL();
    NSString *cert = [NSString stringWithContentsOfURL:[dir URLByAppendingPathComponent:kCertFileName]
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    NSString *key = [NSString stringWithContentsOfURL:[dir URLByAppendingPathComponent:kKeyFileName]
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    NSString *uid = [NSString stringWithContentsOfURL:[dir URLByAppendingPathComponent:kUniqueIdFileName]
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];

    if (cert.length > 0 && key.length > 0 && uid.length > 0) {
        _certificatePEM = cert;
        _privateKeyPEM = key;
        _uniqueId = uid;
        return;
    }

    [self generateAndPersistCredentials];
}

- (void)generateAndPersistCredentials
{
    EVP_PKEY *pkey = EVP_RSA_gen(2048);
    if (pkey == NULL) {
        return;
    }

    X509 *cert = X509_new();
    X509_set_version(cert, 2);
    ASN1_INTEGER_set(X509_get_serialNumber(cert), 0);
    X509_gmtime_adj(X509_getm_notBefore(cert), 0);
    X509_gmtime_adj(X509_getm_notAfter(cert), 60 * 60 * 24 * 365 * 20); // 20 yrs
    X509_set_pubkey(cert, pkey);

    X509_NAME *name = X509_NAME_new();
    X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
                                (unsigned char *)"NVIDIA GameStream Client", -1, -1, 0);
    X509_set_subject_name(cert, name);
    X509_set_issuer_name(cert, name);
    X509_NAME_free(name);

    X509_sign(cert, pkey, EVP_sha256());

    // macOS Security framework requires the traditional PKCS#1 RSA PEM
    // format, not PKCS#8, to import this key later (same requirement noted
    // in the legacy Qt client's identitymanager.cpp).
    BIO *keyBio = BIO_new(BIO_s_mem());
    PEM_write_bio_PrivateKey_traditional(keyBio, pkey, NULL, NULL, 0, NULL, NULL);
    BUF_MEM *keyMem;
    BIO_get_mem_ptr(keyBio, &keyMem);
    NSString *keyPEM = [[NSString alloc] initWithBytes:keyMem->data length:keyMem->length encoding:NSUTF8StringEncoding];
    BIO_free(keyBio);

    BIO *certBio = BIO_new(BIO_s_mem());
    PEM_write_bio_X509(certBio, cert);
    BUF_MEM *certMem;
    BIO_get_mem_ptr(certBio, &certMem);
    NSString *certPEM = [[NSString alloc] initWithBytes:certMem->data length:certMem->length encoding:NSUTF8StringEncoding];
    BIO_free(certBio);

    X509_free(cert);
    EVP_PKEY_free(pkey);

    uint64_t uid = 0;
    RAND_bytes((unsigned char *)&uid, sizeof(uid));
    NSString *uidString = [NSString stringWithFormat:@"%llx", uid];

    _certificatePEM = certPEM;
    _privateKeyPEM = keyPEM;
    _uniqueId = uidString;

    NSURL *dir = SupportDirectoryURL();
    [certPEM writeToURL:[dir URLByAppendingPathComponent:kCertFileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [keyPEM writeToURL:[dir URLByAppendingPathComponent:kKeyFileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [uidString writeToURL:[dir URLByAppendingPathComponent:kUniqueIdFileName] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)certificatePEM
{
    return _certificatePEM;
}

- (NSString *)uniqueId
{
    return _uniqueId;
}

- (EVP_PKEY *)loadPrivateKey
{
    NSData *pemData = [_privateKeyPEM dataUsingEncoding:NSUTF8StringEncoding];
    BIO *bio = BIO_new_mem_buf(pemData.bytes, (int)pemData.length);
    EVP_PKEY *pkey = PEM_read_bio_PrivateKey(bio, NULL, NULL, NULL);
    BIO_free(bio);
    return pkey;
}

- (NSData *)signSHA256:(NSData *)message
{
    EVP_PKEY *pkey = [self loadPrivateKey];
    if (pkey == NULL) {
        return [NSData data];
    }

    EVP_MD_CTX *ctx = EVP_MD_CTX_create();
    EVP_DigestSignInit(ctx, NULL, EVP_sha256(), NULL, pkey);
    EVP_DigestSignUpdate(ctx, message.bytes, message.length);

    size_t sigLen = 0;
    EVP_DigestSignFinal(ctx, NULL, &sigLen);

    NSMutableData *signature = [NSMutableData dataWithLength:sigLen];
    EVP_DigestSignFinal(ctx, (unsigned char *)signature.mutableBytes, &sigLen);
    signature.length = sigLen;

    EVP_MD_CTX_destroy(ctx);
    EVP_PKEY_free(pkey);

    return signature;
}

- (nullable NSData *)pkcs12DataWithPassword:(NSString *)password
{
    NSData *certData = [_certificatePEM dataUsingEncoding:NSUTF8StringEncoding];
    BIO *certBio = BIO_new_mem_buf(certData.bytes, (int)certData.length);
    X509 *cert = PEM_read_bio_X509(certBio, NULL, NULL, NULL);
    BIO_free(certBio);

    EVP_PKEY *pkey = [self loadPrivateKey];
    if (cert == NULL || pkey == NULL) {
        if (cert != NULL) X509_free(cert);
        if (pkey != NULL) EVP_PKEY_free(pkey);
        return nil;
    }

    PKCS12 *p12 = PKCS12_create((char *)password.UTF8String, "selene", pkey, cert, NULL, 0, 0, 0, 0, 0);

    X509_free(cert);
    EVP_PKEY_free(pkey);

    if (p12 == NULL) {
        return nil;
    }

    BIO *p12Bio = BIO_new(BIO_s_mem());
    i2d_PKCS12_bio(p12Bio, p12);
    BUF_MEM *mem;
    BIO_get_mem_ptr(p12Bio, &mem);
    NSData *result = [NSData dataWithBytes:mem->data length:mem->length];
    BIO_free(p12Bio);
    PKCS12_free(p12);

    return result;
}

@end

@implementation GameStreamCrypto

+ (NSData *)randomBytesOfLength:(NSUInteger)length
{
    NSMutableData *data = [NSMutableData dataWithLength:length];
    RAND_bytes((unsigned char *)data.mutableBytes, (int)length);
    return data;
}

+ (NSData *)sha1:(NSData *)data
{
    NSMutableData *digest = [NSMutableData dataWithLength:(NSUInteger)EVP_MD_size(EVP_sha1())];
    unsigned int len = 0;
    EVP_Digest(data.bytes, data.length, (unsigned char *)digest.mutableBytes, &len, EVP_sha1(), NULL);
    return digest;
}

+ (NSData *)sha256:(NSData *)data
{
    NSMutableData *digest = [NSMutableData dataWithLength:(NSUInteger)EVP_MD_size(EVP_sha256())];
    unsigned int len = 0;
    EVP_Digest(data.bytes, data.length, (unsigned char *)digest.mutableBytes, &len, EVP_sha256(), NULL);
    return digest;
}

+ (NSData *)aes128ECBEncrypt:(NSData *)plaintext key:(NSData *)key
{
    if (plaintext.length == 0) {
        return [NSData data];
    }

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_EncryptInit(ctx, EVP_aes_128_ecb(), (const unsigned char *)key.bytes, NULL);
    EVP_CIPHER_CTX_set_padding(ctx, 0);

    NSMutableData *ciphertext = [NSMutableData dataWithLength:plaintext.length];
    int outLen = 0;
    EVP_EncryptUpdate(ctx, (unsigned char *)ciphertext.mutableBytes, &outLen,
                       (const unsigned char *)plaintext.bytes, (int)plaintext.length);

    EVP_CIPHER_CTX_free(ctx);
    return ciphertext;
}

+ (NSData *)aes128ECBDecrypt:(NSData *)ciphertext key:(NSData *)key
{
    if (ciphertext.length == 0) {
        return [NSData data];
    }

    EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
    EVP_DecryptInit(ctx, EVP_aes_128_ecb(), (const unsigned char *)key.bytes, NULL);
    EVP_CIPHER_CTX_set_padding(ctx, 0);

    NSMutableData *plaintext = [NSMutableData dataWithLength:ciphertext.length];
    int outLen = 0;
    EVP_DecryptUpdate(ctx, (unsigned char *)plaintext.mutableBytes, &outLen,
                       (const unsigned char *)ciphertext.bytes, (int)ciphertext.length);

    EVP_CIPHER_CTX_free(ctx);
    return plaintext;
}

+ (nullable NSData *)signatureFromCertificatePEM:(NSString *)certificatePEM
{
    NSData *pemData = [certificatePEM dataUsingEncoding:NSUTF8StringEncoding];
    BIO *bio = BIO_new_mem_buf(pemData.bytes, (int)pemData.length);
    X509 *cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (cert == NULL) {
        return nil;
    }

    const ASN1_BIT_STRING *sig = NULL;
    X509_get0_signature(&sig, NULL, cert);

    NSData *result = [NSData dataWithBytes:ASN1_STRING_get0_data(sig) length:(NSUInteger)ASN1_STRING_length(sig)];
    X509_free(cert);
    return result;
}

+ (BOOL)verifySignature:(NSData *)signature forData:(NSData *)data certificatePEM:(NSString *)certificatePEM
{
    NSData *pemData = [certificatePEM dataUsingEncoding:NSUTF8StringEncoding];
    BIO *bio = BIO_new_mem_buf(pemData.bytes, (int)pemData.length);
    X509 *cert = PEM_read_bio_X509(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (cert == NULL) {
        return NO;
    }

    EVP_PKEY *pubKey = X509_get_pubkey(cert);
    if (pubKey == NULL) {
        X509_free(cert);
        return NO;
    }

    EVP_MD_CTX *ctx = EVP_MD_CTX_create();
    EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, pubKey);
    EVP_DigestVerifyUpdate(ctx, data.bytes, data.length);
    int result = EVP_DigestVerifyFinal(ctx, (const unsigned char *)signature.bytes, (unsigned int)signature.length);

    EVP_MD_CTX_destroy(ctx);
    EVP_PKEY_free(pubKey);
    X509_free(cert);

    return result > 0;
}

@end
