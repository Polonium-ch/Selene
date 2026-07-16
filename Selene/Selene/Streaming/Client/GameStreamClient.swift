import Foundation
import os

private let clientLogger = Logger(subsystem: "ch.polonium.selene", category: "client")

/// An app/game configured on a Sunshine host (Desktop, Steam Big Picture, a
/// specific game, etc).
struct GameStreamApp: Identifiable, Sendable, Hashable, Codable {
    let id: Int
    let name: String
}

/// Fetches the list of apps configured on a paired Sunshine host (`/applist`)
/// and their box art (`/appasset`) - both require mutual TLS with the
/// identity established at pairing time, mirroring the legacy Qt client's
/// `NvHTTP::getAppList()`/`getBoxArt()` (`app/backend/nvhttp.cpp`).
enum GameStreamClient {
    /// Ends whatever app/session is currently running on the host - mirrors
    /// `NvHTTP::quitApp()`. Needed because a `/launch` that never gets
    /// followed by a real teardown leaves the host thinking a game session
    /// is still active, and it'll reject any further `/launch` with
    /// "An app is already running on this host" until this is called (or
    /// the host is restarted).
    @discardableResult
    static func cancelSession(ip: String, httpsPort: UInt16, serverUniqueId: String) async -> Bool {
        guard let session = authenticatedSession(serverUniqueId: serverUniqueId) else {
            return false
        }
        let request = makeRequest(ip: ip, port: httpsPort, command: "cancel", params: [])

        guard let (_, response) = try? await session.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    static func fetchAppList(ip: String, httpsPort: UInt16, serverUniqueId: String) async -> [GameStreamApp]? {
        guard let session = authenticatedSession(serverUniqueId: serverUniqueId) else {
            return nil
        }
        let request = makeRequest(ip: ip, port: httpsPort, command: "applist", params: [])

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseAppList(xml)
    }

    static func fetchBoxArt(appId: Int, ip: String, httpsPort: UInt16, serverUniqueId: String) async -> Data? {
        guard let session = authenticatedSession(serverUniqueId: serverUniqueId) else {
            return nil
        }
        let request = makeRequest(ip: ip, port: httpsPort, command: "appasset", params: [
            ("appid", String(appId)),
            ("AssetType", "2"),
            ("AssetIdx", "0"),
        ])

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            return nil
        }

        return data
    }

    /// Starts (or resumes) an app on the host - the request that must
    /// succeed before `LiStartConnection` can connect. Returns the RTSP
    /// session URL (`sessionUrl0`) the host hands back, which feeds into
    /// `SERVER_INFORMATION.rtspSessionUrl`. Mirrors `NvHTTP::startApp()`
    /// (`app/backend/nvhttp.cpp:200-246`).
    static func launchApp(appId: Int, resuming: Bool, config: StreamSessionConfig, ip: String, httpsPort: UInt16, serverUniqueId: String) async -> String? {
        guard let session = authenticatedSession(serverUniqueId: serverUniqueId) else {
            return nil
        }

        // Matches Limelight.h's SURROUNDAUDIOINFO_FROM_AUDIO_CONFIGURATION -
        // that macro (and MAKE_AUDIO_CONFIGURATION it's built from) isn't
        // visible to Swift as a function-like macro, so the formula is
        // inlined here instead, over the real channel count/mask picked in
        // Settings > Audio (see StreamSessionConfig.make(audioConfig:)).
        let surroundAudioInfo = (Int(config.audioChannelMask) << 16) | Int(config.audioChannelCount)
        let gamepadMask = await GamepadForwarder.attachedGamepadMask

        var params: [(String, String)] = [
            ("appid", String(appId)),
            ("mode", "\(config.width)x\(config.height)x\(config.fps)"),
            ("additionalStates", "1"),
            ("sops", "1"),
            ("rikey", config.remoteInputAesKey.hexEncodedString),
            ("rikeyid", String(config.rikeyId)),
            ("localAudioPlayMode", "0"),
            ("surroundAudioInfo", String(surroundAudioInfo)),
            ("remoteControllersBitmap", String(gamepadMask)),
            ("gcmap", "0"),
            ("gcpersist", "0"),
        ]

        let request = makeRequest(
            ip: ip,
            port: httpsPort,
            command: resuming ? "resume" : "launch",
            params: params,
            extraQuery: String(cString: LiGetLaunchUrlQueryParameters())
        )

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let xml = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
            clientLogger.notice("launch/resume -> HTTP \(status, privacy: .public), body=\(xml.prefix(500), privacy: .public)")
            guard status == 200 else {
                return nil
            }
            return xmlValue(xml, "sessionUrl0")
        } catch {
            clientLogger.error("launch/resume request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func authenticatedSession(serverUniqueId: String) -> URLSession? {
        guard let pinnedCertPEM = PairingStore.pinnedServerCertPEM(serverUniqueId: serverUniqueId) else {
            return nil
        }
        return GameStreamMutualTLS.session(pinnedServerCertPEM: pinnedCertPEM)
    }

    private static func makeRequest(ip: String, port: UInt16, command: String, params: [(String, String)], extraQuery: String? = nil) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = ip
        components.port = Int(port)
        components.path = "/" + command

        var queryItems = [
            URLQueryItem(name: "uniqueid", value: GameStreamIdentity.shared().uniqueId),
            URLQueryItem(name: "uuid", value: UUID().uuidString),
        ]
        queryItems.append(contentsOf: params.map { URLQueryItem(name: $0.0, value: $0.1) })
        components.queryItems = queryItems

        // extraQuery (e.g. moonlight-common-c's LiGetLaunchUrlQueryParameters(),
        // "&corever=1") is already a raw, pre-encoded "&key=value" fragment,
        // so it's appended to the built URL string rather than going through
        // URLQueryItem (which would re-percent-encode the leading "&").
        var url = components.url!
        if let extraQuery, !extraQuery.isEmpty {
            url = URL(string: url.absoluteString + extraQuery) ?? url
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        return request
    }

    private static func xmlValue(_ xml: String, _ tag: String) -> String? {
        let parser = SingleTagXMLParser(trackedTag: tag)
        let xmlParser = XMLParser(data: Data(xml.utf8))
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.value
    }

    private static func parseAppList(_ xml: String) -> [GameStreamApp] {
        let parser = AppListXMLParser()
        let xmlParser = XMLParser(data: Data(xml.utf8))
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.apps
    }
}

private final class AppListXMLParser: NSObject, XMLParserDelegate {
    private(set) var apps: [GameStreamApp] = []
    private var currentId: Int?
    private var currentName: String?
    private var currentElement: String?
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "App":
            currentId = nil
            currentName = nil
        case "ID", "AppTitle":
            currentElement = elementName
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement != nil {
            buffer += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ID":
            currentId = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
            currentElement = nil
        case "AppTitle":
            currentName = buffer
            currentElement = nil
        case "App":
            if let id = currentId {
                apps.append(GameStreamApp(id: id, name: currentName ?? ""))
            }
        default:
            break
        }
    }
}

private final class SingleTagXMLParser: NSObject, XMLParserDelegate {
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
}
