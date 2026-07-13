import Foundation
import os

private let pairingLogger = Logger(subsystem: "ch.useselene.selene", category: "pairing")

/// Result of a pairing attempt - mirrors `NvPairingManager::PairState` in the
/// legacy Qt client (`app/backend/nvpairingmanager.cpp`).
enum PairState: Sendable, Equatable {
    case paired(serverCertPEM: String)
    case pinWrong
    case failed(String)
    case alreadyInProgress
}

/// Ports the NVIDIA GameStream pairing handshake
/// (`app/backend/nvpairingmanager.cpp`'s `pair()`) to Swift: a 5-stage HTTP/HTTPS
/// exchange that proves both sides know the PIN the user typed into Sunshine's
/// web UI, without ever sending the PIN itself over the network. Uses
/// `GameStreamCrypto`/`GameStreamIdentity` (ObjC++/OpenSSL bridge) for the RSA/AES
/// primitives and `URLSession` for the network requests.
///
/// The final stage runs over HTTPS with mutual TLS: our own client identity
/// (`GameStreamIdentity`) presented via a `SecIdentity`, and the server's cert
/// (received in stage 1) pinned exactly like `NvHTTP::handleSslErrors` does -
/// exact-match only, never a blanket "trust everything".
enum GameStreamPairing {
    static func pair(ip: String, httpPort: UInt16, httpsPort: UInt16, appVersion: String?, pin: String) async -> PairState {
        let identity = GameStreamIdentity.shared()

        // Sunshine (unlike some real NVIDIA GFE builds) expects/requires our
        // real uniqueid during pairing - see NvHTTP's useTrueUid, which is
        // true whenever the host isn't real Nvidia server software.
        let ownUniqueId = identity.uniqueId

        let serverMajorVersion = appVersion?.split(separator: ".").first.flatMap { Int($0) } ?? 0
        let useSHA256 = serverMajorVersion >= 7
        let hashLength = useSHA256 ? 32 : 20
        func hash(_ data: Data) -> Data {
            useSHA256 ? GameStreamCrypto.sha256(data) : GameStreamCrypto.sha1(data)
        }

        let ownCertHex = Data(identity.certificatePEM.utf8).hexEncodedString

        let salt = GameStreamCrypto.randomBytes(ofLength: 16)
        let saltedPin = salt + Data(pin.utf8)
        let aesKey = hash(saltedPin).prefix(16)

        func unpair() async {
            _ = await request(ip: ip, port: httpPort, https: false, command: "pair", uniqueId: ownUniqueId, params: [])
        }

        // Stage 1: exchange certificates, get the server's. Sunshine holds this
        // request open (no response at all) until the user actually submits the
        // matching PIN on its web UI, so - like the legacy Qt client, which
        // passes timeoutMs=0 (no timeout) for this specific stage - we need to
        // wait far longer than the other stages' quick round-trips.
        guard let stage1 = await request(ip: ip, port: httpPort, https: false, command: "pair", uniqueId: ownUniqueId, timeout: 300, params: [
            ("devicename", "roth"),
            ("updateState", "1"),
            ("phrase", "getservercert"),
            ("salt", salt.hexEncodedString),
            ("clientcert", ownCertHex),
        ]) else {
            return .failed("Stage 1 (getservercert) request failed")
        }
        guard xmlValue(stage1, "paired") == "1" else {
            return .failed("Stage 1: server reported not paired")
        }
        guard let plainCertHex = xmlValue(stage1, "plaincert"),
              let serverCertData = Data(hexString: plainCertHex), !serverCertData.isEmpty,
              let serverCertPEM = String(data: serverCertData, encoding: .utf8) else {
            await unpair()
            return .alreadyInProgress
        }
        guard let serverCertDER = serverCertPEM.derFromPEMCertificate() else {
            await unpair()
            return .failed("Failed to parse server certificate")
        }

        // Stage 2: prove we know the PIN by encrypting a random challenge;
        // the server must decrypt-and-echo it back correctly.
        let randomChallenge = GameStreamCrypto.randomBytes(ofLength: 16)
        let encryptedChallenge = GameStreamCrypto.aes128ECBEncrypt(randomChallenge, key: Data(aesKey))
        guard let stage2 = await request(ip: ip, port: httpPort, https: false, command: "pair", uniqueId: ownUniqueId, params: [
            ("devicename", "roth"),
            ("updateState", "1"),
            ("clientchallenge", encryptedChallenge.hexEncodedString),
        ]) else {
            return .failed("Stage 2 (clientchallenge) request failed")
        }
        guard xmlValue(stage2, "paired") == "1" else {
            await unpair()
            return .failed("Stage 2: server reported not paired")
        }
        guard let challengeResponseHex = xmlValue(stage2, "challengeresponse"),
              let challengeResponseCipher = Data(hexString: challengeResponseHex) else {
            await unpair()
            return .failed("Stage 2: missing challengeresponse")
        }
        let challengeResponseData = GameStreamCrypto.aes128ECBDecrypt(challengeResponseCipher, key: Data(aesKey))
        guard challengeResponseData.count >= hashLength + 16 else {
            await unpair()
            return .failed("Stage 2: challengeresponse too short")
        }

        // Stage 3: prove our own identity back to the server, and receive its
        // proof (a signed shared secret) that it also knows the PIN.
        let clientSecretData = GameStreamCrypto.randomBytes(ofLength: 16)
        let serverResponse = challengeResponseData.slice(0..<hashLength)
        let serverChallengeRemainder = challengeResponseData.slice(hashLength..<(hashLength + 16))

        guard let ownCertSignature = GameStreamCrypto.signature(fromCertificatePEM: identity.certificatePEM) else {
            await unpair()
            return .failed("Failed to read own certificate signature")
        }

        var challengeResponse = Data()
        challengeResponse.append(serverChallengeRemainder)
        challengeResponse.append(ownCertSignature)
        challengeResponse.append(clientSecretData)

        var paddedHash = hash(challengeResponse)
        if paddedHash.count < 32 {
            paddedHash.append(Data(repeating: 0, count: 32 - paddedHash.count))
        }
        let encryptedChallengeResponseHash = GameStreamCrypto.aes128ECBEncrypt(paddedHash, key: Data(aesKey))

        guard let stage3 = await request(ip: ip, port: httpPort, https: false, command: "pair", uniqueId: ownUniqueId, params: [
            ("devicename", "roth"),
            ("updateState", "1"),
            ("serverchallengeresp", encryptedChallengeResponseHash.hexEncodedString),
        ]) else {
            return .failed("Stage 3 (serverchallengeresp) request failed")
        }
        guard xmlValue(stage3, "paired") == "1" else {
            await unpair()
            return .failed("Stage 3: server reported not paired")
        }
        guard let pairingSecretHex = xmlValue(stage3, "pairingsecret"),
              let pairingSecret = Data(hexString: pairingSecretHex), pairingSecret.count > 16 else {
            await unpair()
            return .failed("Stage 3: missing/invalid pairingsecret")
        }
        let serverSecret = pairingSecret.slice(0..<16)
        let serverSignature = pairingSecret.subdata(in: pairingSecret.index(pairingSecret.startIndex, offsetBy: 16)..<pairingSecret.endIndex)

        guard GameStreamCrypto.verifySignature(serverSignature, for: serverSecret, certificatePEM: serverCertPEM) else {
            await unpair()
            return .failed("MITM detected: server signature verification failed")
        }

        guard let serverCertSignature = GameStreamCrypto.signature(fromCertificatePEM: serverCertPEM) else {
            await unpair()
            return .failed("Failed to read server certificate signature")
        }

        var expectedResponseData = Data()
        expectedResponseData.append(randomChallenge)
        expectedResponseData.append(serverCertSignature)
        expectedResponseData.append(serverSecret)

        guard hash(expectedResponseData) == serverResponse else {
            await unpair()
            return .pinWrong
        }

        // Stage 4: send our own signed secret so the server can verify us too.
        var clientPairingSecret = Data()
        clientPairingSecret.append(clientSecretData)
        clientPairingSecret.append(identity.signSHA256(clientSecretData))

        guard let stage4 = await request(ip: ip, port: httpPort, https: false, command: "pair", uniqueId: ownUniqueId, params: [
            ("devicename", "roth"),
            ("updateState", "1"),
            ("clientpairingsecret", clientPairingSecret.hexEncodedString),
        ]) else {
            return .failed("Stage 4 (clientpairingsecret) request failed")
        }
        guard xmlValue(stage4, "paired") == "1" else {
            await unpair()
            return .failed("Stage 4: server reported not paired")
        }

        // Stage 5: confirm over HTTPS with mutual TLS - this is what actually
        // finalizes pairing server-side.
        guard let clientIdentity = GameStreamMutualTLS.makeClientSecIdentity() else {
            await unpair()
            return .failed("Failed to build client TLS identity")
        }
        let tlsDelegate = TLSPinningDelegate(pinnedServerCertDER: serverCertDER, clientIdentity: clientIdentity)

        guard let stage5 = await request(ip: ip, port: httpsPort, https: true, command: "pair", uniqueId: ownUniqueId, params: [
            ("devicename", "roth"),
            ("updateState", "1"),
            ("phrase", "pairchallenge"),
        ], tlsDelegate: tlsDelegate) else {
            return .failed("Stage 5 (pairchallenge) request failed")
        }
        guard xmlValue(stage5, "paired") == "1" else {
            await unpair()
            return .failed("Stage 5: server reported not paired")
        }

        return .paired(serverCertPEM: serverCertPEM)
    }

    // MARK: - Networking

    private static func request(
        ip: String,
        port: UInt16,
        https: Bool,
        command: String,
        uniqueId: String,
        timeout: TimeInterval = 5,
        params: [(String, String)],
        tlsDelegate: TLSPinningDelegate? = nil
    ) async -> String? {
        var components = URLComponents()
        components.scheme = https ? "https" : "http"
        components.host = ip
        components.port = Int(port)
        components.path = "/" + command

        var queryItems = [
            URLQueryItem(name: "uniqueid", value: uniqueId),
            URLQueryItem(name: "uuid", value: UUID().uuidString),
        ]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.0, value: $0.1) })
        components.queryItems = queryItems

        guard let url = components.url else {
            pairingLogger.error("failed to build URL for command=\(command, privacy: .public)")
            return nil
        }
        pairingLogger.notice("-> \(command, privacy: .public) \(url.absoluteString.prefix(120), privacy: .public)...")

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = timeout

        let session: URLSession
        if let tlsDelegate {
            session = URLSession(configuration: .ephemeral, delegate: tlsDelegate, delegateQueue: nil)
        } else {
            session = .shared
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                pairingLogger.error("<- \(command, privacy: .public): response isn't HTTPURLResponse")
                return nil
            }
            guard httpResponse.statusCode == 200 else {
                pairingLogger.error("<- \(command, privacy: .public): HTTP \(httpResponse.statusCode, privacy: .public)")
                return nil
            }
            let body = String(data: data, encoding: .utf8)
            pairingLogger.notice("<- \(command, privacy: .public): HTTP 200, body=\(body?.prefix(300) ?? "nil", privacy: .public)")
            return body
        } catch {
            pairingLogger.error("<- \(command, privacy: .public) FAILED: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

}

// MARK: - Small helpers

private func xmlValue(_ xml: String, _ tag: String) -> String? {
    let parser = SingleUseXMLParser(trackedTag: tag)
    let xmlParser = XMLParser(data: Data(xml.utf8))
    xmlParser.delegate = parser
    xmlParser.parse()
    return parser.value
}

private final class SingleUseXMLParser: NSObject, XMLParserDelegate {
    private let trackedTag: String
    private(set) var value: String?
    private var isInTrackedElement = false
    private var buffer = ""

    init(trackedTag: String) {
        self.trackedTag = trackedTag
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == trackedTag {
            isInTrackedElement = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInTrackedElement {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == trackedTag {
            value = buffer
            isInTrackedElement = false
        }
    }
}

private extension Data {
    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        guard hexString.count % 2 == 0 else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        self = data
    }

    func slice(_ range: Range<Int>) -> Data {
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(startIndex, offsetBy: range.upperBound)
        return subdata(in: start..<end)
    }
}
