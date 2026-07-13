import Foundation
import Security

/// Builds authenticated `URLSession`s for talking to a paired Sunshine host
/// over HTTPS with mutual TLS: our own client identity presented via a
/// `SecIdentity`, and the host's certificate (captured at pairing time)
/// pinned exactly - never a blanket trust-all, mirroring the legacy Qt
/// client's `NvHTTP::handleSslErrors`. Shared by `GameStreamPairing` (stage 5)
/// and `GameStreamClient` (`/applist`, `/appasset`, and later `/launch`).
enum GameStreamMutualTLS {
    // Importing a PKCS#12 blob asks Keychain to authorize the resulting
    // identity's use - caching it means the user only sees that prompt once
    // per launch instead of on every single pairing/applist/appasset request.
    // Benign worst case if two calls race before the cache is warm: both
    // import the same PKCS#12 blob and get equivalent identities.
    private nonisolated(unsafe) static var cachedIdentity: SecIdentity?

    static func session(pinnedServerCertPEM: String) -> URLSession? {
        guard let serverCertDER = pinnedServerCertPEM.derFromPEMCertificate(),
              let clientIdentity = makeClientSecIdentity() else {
            return nil
        }
        let delegate = TLSPinningDelegate(pinnedServerCertDER: serverCertDER, clientIdentity: clientIdentity)
        return URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    static func makeClientSecIdentity() -> SecIdentity? {
        if let cachedIdentity {
            return cachedIdentity
        }

        let password = "selene"
        let identity = GameStreamIdentity.shared()
        guard let p12Data = identity.pkcs12Data(withPassword: password) else {
            return nil
        }

        let options = [kSecImportExportPassphrase as String: password]
        var rawItems: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &rawItems)
        guard status == errSecSuccess,
              let items = rawItems as? [[String: Any]],
              let firstItem = items.first,
              let identityRef = firstItem[kSecImportItemIdentity as String] else {
            return nil
        }

        let secIdentity = (identityRef as! SecIdentity)
        cachedIdentity = secIdentity
        return secIdentity
    }
}

/// Handles the mTLS challenge: presents our own client identity, and accepts
/// the server's certificate only if it's byte-identical to the pinned one.
final class TLSPinningDelegate: NSObject, URLSessionDelegate {
    let pinnedServerCertDER: Data
    let clientIdentity: SecIdentity

    init(pinnedServerCertDER: Data, clientIdentity: SecIdentity) {
        self.pinnedServerCertDER = pinnedServerCertDER
        self.clientIdentity = clientIdentity
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = challenge.protectionSpace.serverTrust,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let leafCert = chain.first else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let leafCertData = SecCertificateCopyData(leafCert) as Data
            if leafCertData == pinnedServerCertDER {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }

        case NSURLAuthenticationMethodClientCertificate:
            completionHandler(.useCredential, URLCredential(identity: clientIdentity, certificates: nil, persistence: .forSession))

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension String {
    /// Decodes a PEM certificate's base64 body into raw DER bytes, for
    /// byte-comparison against a `SecCertificate`'s DER representation.
    func derFromPEMCertificate() -> Data? {
        let base64Body = split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64Body)
    }
}
