import Foundation

/// A Sunshine/GameStream host's `/serverinfo` response fields this client
/// needs: the display name, protocol/app version (picks the pairing hash
/// algorithm - see `GameStreamPairing`), and the server's own stable identity
/// (used as the persistence key for "have we paired with this host", since
/// mDNS names/IPs can change but this doesn't - mirrors how the legacy Qt
/// client keys `NvComputer` persistence off this same field).
struct SunshineServerInfo: Sendable {
    var hostname: String?
    var appVersion: String?
    var uniqueId: String?
    var httpsPort: UInt16?
    /// The app ID currently running on the host, or nil if nothing is -
    /// mirrors the legacy Qt client's `NvHTTP::getCurrentGame()`, which
    /// drives whether an app tile shows "Resume"/"Quit" instead of "Launch".
    var currentGameAppId: Int?
}

/// Fetches `/serverinfo` over its unauthenticated plain-HTTP endpoint.
///
/// The Bonjour service name `HostDiscoveryService` resolves from `_nvstream._tcp`
/// is not the same as the "Sunshine Name" the user sets in Sunshine's web UI -
/// the legacy Qt client (`app/backend/nvcomputer.cpp`) never uses the mDNS name
/// for display either; it always follows up an mDNS-discovered address with this
/// same HTTP call and reads fields out of the response
/// (`app/backend/nvhttp.cpp`'s `getServerInfo()`/`getXmlString()`).
/// No pairing is required for this - GFE/Sunshine serve `/serverinfo` unauthenticated.
enum SunshineServerInfoFetcher {
    static func fetch(ip: String, port: UInt16) async -> SunshineServerInfo? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = ip
        components.port = Int(port)
        components.path = "/serverinfo"
        components.queryItems = [
            URLQueryItem(name: "uniqueid", value: "0123456789ABCDEF"),
            URLQueryItem(name: "uuid", value: UUID().uuidString),
        ]
        guard let url = components.url else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return nil
        }

        let parser = ServerInfoXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            return nil
        }

        return SunshineServerInfo(
            hostname: nonEmpty(parser.fields["hostname"]),
            appVersion: nonEmpty(parser.fields["appversion"]),
            uniqueId: nonEmpty(parser.fields["uniqueid"]),
            httpsPort: parser.fields["HttpsPort"].flatMap { UInt16($0) },
            // 0 means "nothing running" (GFE/Sunshine convention - see
            // NvHTTP::getCurrentGame()), so normalize that to nil.
            currentGameAppId: parser.fields["currentgame"].flatMap { Int($0) }.flatMap { $0 == 0 ? nil : $0 }
        )
    }

    private static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private final class ServerInfoXMLParser: NSObject, XMLParserDelegate {
    private(set) var fields: [String: String] = [:]
    private static let trackedElements: Set<String> = ["hostname", "appversion", "uniqueid", "HttpsPort", "currentgame"]
    private var currentElement: String?
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if Self.trackedElements.contains(elementName) {
            currentElement = elementName
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement != nil {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if currentElement == elementName {
            fields[elementName] = buffer
            currentElement = nil
        }
    }
}
