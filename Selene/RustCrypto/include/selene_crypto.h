#ifndef SELENE_CRYPTO_H
#define SELENE_CRYPTO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Owned buffer returned from Rust. `ptr` is NULL when `len` is 0 or on
/// failure - callers should treat NULL+0 the same as an empty result unless
/// a function's doc says NULL specifically means failure. Always release
/// with `selene_crypto_free_buffer`, even when `ptr` is NULL.
typedef struct {
    uint8_t *ptr;
    size_t len;
} SeleneCryptoBuffer;

void selene_crypto_free_buffer(SeleneCryptoBuffer buf);

typedef struct SeleneIdentity SeleneIdentity;

/// Loads the persisted identity from `support_dir_utf8` (NUL-terminated
/// UTF-8 path), generating and persisting a new one if none exists yet.
/// Returns NULL only if generation fails outright. The returned pointer is
/// intentionally leaked for the process lifetime (mirrors the previous
/// Objective-C `+shared` singleton, which was never deallocated either).
SeleneIdentity *selene_identity_shared(const char *support_dir_utf8);

/// PEM-encoded self-signed X.509 certificate (CN="NVIDIA GameStream Client").
SeleneCryptoBuffer selene_identity_certificate_pem(const SeleneIdentity *identity);

/// Lowercase hex-encoded 64-bit unique ID, sent as `uniqueid` on every
/// GameStream HTTP request.
SeleneCryptoBuffer selene_identity_unique_id(const SeleneIdentity *identity);

/// RSA-SHA256 signature over `message`.
SeleneCryptoBuffer selene_identity_sign_sha256(const SeleneIdentity *identity,
                                                const uint8_t *message,
                                                size_t message_len);

/// PKCS#12 bundle (cert + private key, friendly name "selene") for
/// `SecIdentity` import. `ptr` is NULL on failure.
SeleneCryptoBuffer selene_identity_pkcs12(const SeleneIdentity *identity,
                                           const char *password_utf8);

SeleneCryptoBuffer selene_crypto_random_bytes(size_t length);
SeleneCryptoBuffer selene_crypto_sha1(const uint8_t *data, size_t len);
SeleneCryptoBuffer selene_crypto_sha256(const uint8_t *data, size_t len);

/// `key` must point to 16 bytes (AES-128). No padding, matching the legacy
/// `EVP_CIPHER_CTX_set_padding(ctx, 0)` behavior.
SeleneCryptoBuffer selene_crypto_aes128_ecb_encrypt(const uint8_t *plaintext,
                                                     size_t plaintext_len,
                                                     const uint8_t *key);
SeleneCryptoBuffer selene_crypto_aes128_ecb_decrypt(const uint8_t *ciphertext,
                                                     size_t ciphertext_len,
                                                     const uint8_t *key);

/// Raw ASN.1 signature bytes embedded in `certificate_pem_utf8` (its own
/// self-signature). `ptr` is NULL if the certificate can't be parsed.
SeleneCryptoBuffer selene_crypto_signature_from_certificate_pem(const char *certificate_pem_utf8);

/// Verifies `signature` over `data` using the public key extracted from
/// `certificate_pem_utf8` (RSA-SHA256).
bool selene_crypto_verify_signature(const uint8_t *signature, size_t signature_len,
                                     const uint8_t *data, size_t data_len,
                                     const char *certificate_pem_utf8);

#ifdef __cplusplus
}
#endif

#endif /* SELENE_CRYPTO_H */
