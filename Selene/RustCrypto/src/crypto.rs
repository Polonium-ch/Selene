use openssl::hash::{hash, MessageDigest};
use openssl::rand::rand_bytes;
use openssl::sign::Verifier;
use openssl::symm::{Cipher, Crypter, Mode};
use openssl::x509::X509;

pub fn random_bytes(length: usize) -> Vec<u8> {
    let mut buf = vec![0u8; length];
    let _ = rand_bytes(&mut buf);
    buf
}

pub fn sha1(data: &[u8]) -> Vec<u8> {
    hash(MessageDigest::sha1(), data)
        .map(|d| d.to_vec())
        .unwrap_or_default()
}

pub fn sha256(data: &[u8]) -> Vec<u8> {
    hash(MessageDigest::sha256(), data)
        .map(|d| d.to_vec())
        .unwrap_or_default()
}

pub fn aes128_ecb_encrypt(plaintext: &[u8], key: &[u8]) -> Vec<u8> {
    if plaintext.is_empty() {
        return Vec::new();
    }
    aes128_ecb(Mode::Encrypt, plaintext, key).unwrap_or_default()
}

pub fn aes128_ecb_decrypt(ciphertext: &[u8], key: &[u8]) -> Vec<u8> {
    if ciphertext.is_empty() {
        return Vec::new();
    }
    aes128_ecb(Mode::Decrypt, ciphertext, key).unwrap_or_default()
}

// No padding, and only `update` is called (no `finalize`) - matches the
// legacy ObjC++ implementation exactly, including its behavior of silently
// dropping a non-block-aligned trailing remainder. Every call site today
// only ever passes 16- or 32-byte (block-aligned) buffers, so this has
// never been observed to matter in practice.
fn aes128_ecb(mode: Mode, input: &[u8], key: &[u8]) -> Result<Vec<u8>, openssl::error::ErrorStack> {
    let mut crypter = Crypter::new(Cipher::aes_128_ecb(), mode, key, None)?;
    crypter.pad(false);
    let mut out = vec![0u8; input.len() + Cipher::aes_128_ecb().block_size()];
    let count = crypter.update(input, &mut out)?;
    out.truncate(count);
    Ok(out)
}

pub fn signature_from_certificate_pem(certificate_pem: &str) -> Option<Vec<u8>> {
    let cert = X509::from_pem(certificate_pem.as_bytes()).ok()?;
    Some(cert.signature().as_slice().to_vec())
}

pub fn verify_signature(signature: &[u8], data: &[u8], certificate_pem: &str) -> bool {
    verify_signature_inner(signature, data, certificate_pem).unwrap_or(false)
}

fn verify_signature_inner(
    signature: &[u8],
    data: &[u8],
    certificate_pem: &str,
) -> Result<bool, openssl::error::ErrorStack> {
    let cert = X509::from_pem(certificate_pem.as_bytes())?;
    let pubkey = cert.public_key()?;
    let mut verifier = Verifier::new(MessageDigest::sha256(), &pubkey)?;
    verifier.update(data)?;
    Ok(verifier.verify(signature)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn from_hex(s: &str) -> Vec<u8> {
        (0..s.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn sha1_matches_known_vector() {
        assert_eq!(
            sha1(b"abc"),
            from_hex("a9993e364706816aba3e25717850c26c9cd0d89d")
        );
    }

    #[test]
    fn sha256_matches_known_vector() {
        assert_eq!(
            sha256(b"abc"),
            from_hex("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        );
    }

    #[test]
    fn aes128_ecb_round_trip() {
        let key = [0u8; 16];
        let plaintext = b"0123456789abcdef0123456789abcdef".to_vec(); // 2 blocks
        let ciphertext = aes128_ecb_encrypt(&plaintext, &key);
        assert_eq!(ciphertext.len(), plaintext.len());
        assert_ne!(ciphertext, plaintext);
        let decrypted = aes128_ecb_decrypt(&ciphertext, &key);
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn aes128_ecb_empty_input_is_empty_output() {
        let key = [0u8; 16];
        assert!(aes128_ecb_encrypt(&[], &key).is_empty());
        assert!(aes128_ecb_decrypt(&[], &key).is_empty());
    }

    #[test]
    fn random_bytes_has_requested_length_and_is_not_all_zero() {
        let bytes = random_bytes(32);
        assert_eq!(bytes.len(), 32);
        assert!(bytes.iter().any(|&b| b != 0));
    }
}
