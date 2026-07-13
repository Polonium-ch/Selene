import Foundation

/// Fetches a Sunshine/GameStream host's real configured display name via its
/// unauthenticated `/serverinfo` HTTP endpoint.
///
/// The Bonjour service name `HostDiscoveryService` resolves from `_nvstream._tcp`
/// is not the same as the "Sunshine Name" the user sets in Sunshine's web UI -
/// the legacy Qt client (`app/backend/nvcomputer.cpp`) never uses the mDNS name
/// for display either; it always follows up an mDNS-discovered address with this
/// same HTTP call and reads the `<hostname>` field from the response
/// (`app/backend/nvhttp.cpp`'s `getServerInfo()`/`getXmlString(..., "hostname")`).
/// No pairing is required for this - GFE/Sunshine serve `<hostname>` unauthenticated.
enum SunshineServerInfo {
    static func fetchHostname(ip: String, port: UInt16) async -> String? {
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

        let parser = HostnameXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse(), let hostname = parser.hostname else {
            return nil
        }

        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private final class HostnameXMLParser: NSObject, XMLParserDelegate {
    private(set) var hostname: String?
    private var isInHostnameElement = false
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "hostname" {
            isInHostnameElement = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInHostnameElement {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "hostname" {
            hostname = buffer
            isInHostnameElement = false
        }
    }
}
