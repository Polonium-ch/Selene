use openssl::asn1::Asn1Time;
use openssl::bn::BigNum;
use openssl::hash::MessageDigest;
use openssl::pkcs12::Pkcs12;
use openssl::pkey::{PKey, Private};
use openssl::rsa::Rsa;
use openssl::sign::Signer;
use openssl::x509::{X509NameBuilder, X509};
use std::fs;
use std::path::Path;

const CERT_FILE: &str = "identity_cert.pem";
const KEY_FILE: &str = "identity_key.pem";
const UID_FILE: &str = "identity_uniqueid.txt";
const COMMON_NAME: &str = "NVIDIA GameStream Client";
const VALIDITY_DAYS: u32 = 365 * 20;
const PKCS12_FRIENDLY_NAME: &str = "selene";

/// Mirrors the legacy Qt client's `identitymanager.cpp`: same CN, key
/// size, and validity, so the resulting cert/key are indistinguishable to
/// a Sunshine host.
pub struct Identity {
    pub certificate_pem: String,
    pub unique_id: String,
    private_key_pem: String,
}

impl Identity {
    pub fn load_or_create(support_dir: &Path) -> Option<Identity> {
        if let Some(id) = Self::load(support_dir) {
            return Some(id);
        }
        let id = Self::generate().ok()?;
        id.persist(support_dir);
        Some(id)
    }

    fn load(dir: &Path) -> Option<Identity> {
        let cert = fs::read_to_string(dir.join(CERT_FILE)).ok()?;
        let key = fs::read_to_string(dir.join(KEY_FILE)).ok()?;
        let uid = fs::read_to_string(dir.join(UID_FILE)).ok()?;
        if cert.is_empty() || key.is_empty() || uid.is_empty() {
            return None;
        }
        Some(Identity {
            certificate_pem: cert,
            private_key_pem: key,
            unique_id: uid,
        })
    }

    fn generate() -> Result<Identity, openssl::error::ErrorStack> {
        let rsa = Rsa::generate(2048)?;
        // macOS Security framework requires the traditional PKCS#1 RSA PEM
        // format, not PKCS#8, to import this key later (same requirement
        // noted in the legacy Qt client's identitymanager.cpp).
        let private_key_pem =
            String::from_utf8(rsa.private_key_to_pem()?).expect("OpenSSL PEM output is ASCII");
        let pkey = PKey::from_rsa(rsa)?;

        let mut builder = X509::builder()?;
        builder.set_version(2)?;
        let serial = BigNum::from_u32(0)?.to_asn1_integer()?;
        builder.set_serial_number(&serial)?;
        let not_before = Asn1Time::days_from_now(0)?;
        builder.set_not_before(&not_before)?;
        let not_after = Asn1Time::days_from_now(VALIDITY_DAYS)?;
        builder.set_not_after(&not_after)?;
        builder.set_pubkey(&pkey)?;

        let mut name_builder = X509NameBuilder::new()?;
        name_builder.append_entry_by_text("CN", COMMON_NAME)?;
        let name = name_builder.build();
        builder.set_subject_name(&name)?;
        builder.set_issuer_name(&name)?;
        builder.sign(&pkey, MessageDigest::sha256())?;
        let cert = builder.build();
        let certificate_pem =
            String::from_utf8(cert.to_pem()?).expect("OpenSSL PEM output is ASCII");

        let mut uid_bytes = [0u8; 8];
        openssl::rand::rand_bytes(&mut uid_bytes)?;
        let unique_id = format!("{:x}", u64::from_ne_bytes(uid_bytes));

        Ok(Identity {
            certificate_pem,
            unique_id,
            private_key_pem,
        })
    }

    fn persist(&self, dir: &Path) {
        let _ = fs::create_dir_all(dir);
        let _ = fs::write(dir.join(CERT_FILE), &self.certificate_pem);
        let _ = fs::write(dir.join(KEY_FILE), &self.private_key_pem);
        let _ = fs::write(dir.join(UID_FILE), &self.unique_id);
    }

    fn load_private_key(&self) -> Option<PKey<Private>> {
        PKey::private_key_from_pem(self.private_key_pem.as_bytes()).ok()
    }

    pub fn sign_sha256(&self, message: &[u8]) -> Vec<u8> {
        let pkey = match self.load_private_key() {
            Some(k) => k,
            None => return Vec::new(),
        };
        Self::sign_sha256_inner(&pkey, message).unwrap_or_default()
    }

    fn sign_sha256_inner(
        pkey: &PKey<Private>,
        message: &[u8],
    ) -> Result<Vec<u8>, openssl::error::ErrorStack> {
        let mut signer = Signer::new(MessageDigest::sha256(), pkey)?;
        signer.update(message)?;
        signer.sign_to_vec()
    }

    pub fn pkcs12(&self, password: &str) -> Option<Vec<u8>> {
        let cert = X509::from_pem(self.certificate_pem.as_bytes()).ok()?;
        let pkey = self.load_private_key()?;
        let pkcs12 = Pkcs12::builder()
            .name(PKCS12_FRIENDLY_NAME)
            .pkey(&pkey)
            .cert(&cert)
            .build2(password)
            .ok()?;
        pkcs12.to_der().ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto;

    #[test]
    fn generated_key_is_pkcs1_traditional_format() {
        let id = Identity::generate().expect("generation should succeed");
        assert!(
            id.private_key_pem.starts_with("-----BEGIN RSA PRIVATE KEY-----"),
            "expected PKCS#1 traditional format, got: {}",
            &id.private_key_pem[..40.min(id.private_key_pem.len())]
        );
    }

    #[test]
    fn certificate_has_expected_common_name() {
        let id = Identity::generate().expect("generation should succeed");
        assert!(id.certificate_pem.contains("-----BEGIN CERTIFICATE-----"));
        // CN is DER-encoded inside the cert, not literally present as PEM
        // text, so round-trip through a parse instead of a substring check.
        let cert = X509::from_pem(id.certificate_pem.as_bytes()).unwrap();
        let cn = cert
            .subject_name()
            .entries()
            .next()
            .expect("subject should have a CN entry")
            .data()
            .to_string()
            .expect("CN entry should be valid UTF-8");
        assert_eq!(cn, COMMON_NAME);
    }

    #[test]
    fn sign_then_verify_round_trip() {
        let id = Identity::generate().expect("generation should succeed");
        let message = b"pairing challenge";
        let signature = id.sign_sha256(message);
        assert!(!signature.is_empty());
        assert!(crypto::verify_signature(
            &signature,
            message,
            &id.certificate_pem
        ));
    }

    #[test]
    fn pkcs12_export_succeeds() {
        let id = Identity::generate().expect("generation should succeed");
        let der = id.pkcs12("test-password").expect("pkcs12 export should succeed");
        assert!(!der.is_empty());
    }

    #[test]
    fn load_or_create_persists_and_reloads_identical_identity() {
        let dir = std::env::temp_dir().join(format!(
            "selene-crypto-test-{}-load-or-create",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);

        let first = Identity::load_or_create(&dir).expect("first load_or_create should succeed");
        let second = Identity::load_or_create(&dir).expect("second load_or_create should succeed");

        assert_eq!(first.certificate_pem, second.certificate_pem);
        assert_eq!(first.unique_id, second.unique_id);

        let _ = fs::remove_dir_all(&dir);
    }
}
