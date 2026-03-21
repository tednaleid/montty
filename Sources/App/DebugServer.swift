// ABOUTME: Debug-only HTTP server for programmatic terminal interaction.
// ABOUTME: Exposes /surfaces, /type, /key, /screen, /screenshot, /state, /action on localhost:9876.
#if DEBUG
import AppKit
import GhosttyKit
import Network
/// Minimal HTTP server for debug inspection and automation of the terminal.
/// Only compiled into Debug builds -- never ships in Release.
/// See docs/debug-server.md for usage.
enum DebugServer {
    private nonisolated(unsafe) static var listener: NWListener?

    // MARK: - Lifecycle
    static func start() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: 9876)

        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { connection in
                handleConnection(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[DebugServer] Listening on localhost:9876")
                case .failed(let error):
                    print("[DebugServer] Failed: \(error)")
                default:
                    break
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            print("[DebugServer] Could not create listener: \(error)")
        }
    }

    static func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling
    private static func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { data, _, _, error in
            if let error = error {
                print("[DebugServer] Receive error: \(error)")
                connection.cancel()
                return
            }
            guard let data = data else {
                connection.cancel()
                return
            }
            let request = parseRequest(data)
            routeRequest(request, connection: connection)
        }
    }

    // MARK: - HTTP parsing
    struct HTTPRequest {
        var method: String
        var path: String
        var query: [String: String]
        var body: String
    }

    static func parseRequest(_ data: Data) -> HTTPRequest {
        let raw = String(data: data, encoding: .utf8) ?? ""
        let lines = raw.split(separator: "\r\n", omittingEmptySubsequences: false)

        var method = "GET"
        var fullPath = "/"
        if let requestLine = lines.first {
            let parts = requestLine.split(separator: " ", maxSplits: 2)
            if parts.count >= 2 {
                method = String(parts[0])
                fullPath = String(parts[1])
            }
        }

        var path = fullPath
        var query: [String: String] = [:]
        if let qIndex = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<qIndex])
            let queryString = String(fullPath[fullPath.index(after: qIndex)...])
            for param in queryString.split(separator: "&") {
                let keyValue = param.split(separator: "=", maxSplits: 1)
                if keyValue.count == 2 {
                    let key = String(keyValue[0]).removingPercentEncoding ?? String(keyValue[0])
                    let value = String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1])
                    query[key] = value
                }
            }
        }

        var body = ""
        if let blankLineIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(blankLineIndex + 1)...]
            body = bodyLines.joined(separator: "\r\n")
        }

        return HTTPRequest(method: method, path: path, query: query, body: body)
    }

    // MARK: - Key mapping
    // Map a key name to a text character for direct input.
    // swiftlint:disable:next cyclomatic_complexity
    static func keyToText(_ name: String) -> String? {
        switch name.lowercased() {
        case "return", "enter":     return "\r"
        case "tab":                 return "\t"
        case "space":               return " "
        case "escape", "esc":       return "\u{1B}"
        case "backspace", "delete": return "\u{7F}"
        case "ctrl+c":              return "\u{03}"
        case "ctrl+d":              return "\u{04}"
        case "ctrl+z":              return "\u{1A}"
        case "ctrl+l":              return "\u{0C}"
        case "ctrl+a":              return "\u{01}"
        case "ctrl+e":              return "\u{05}"
        case "ctrl+k":              return "\u{0B}"
        case "ctrl+u":              return "\u{15}"
        case "ctrl+w":              return "\u{17}"
        case "ctrl+r":              return "\u{12}"
        default:                    return nil
        }
    }

    // Pass through as-is -- Ghostty actions are strings like "copy_to_clipboard".
    static func keyActionString(for name: String) -> String { name }

    // MARK: - Response helpers
    static func formatJSONResponse(_ dict: [String: Any], status: Int = 200) -> Data {
        DebugHTTP.jsonResponse(dict, status: status)
    }

    static func sendJSON(
        _ dict: [String: Any], status: Int = 200, connection: NWConnection
    ) {
        let response = DebugHTTP.jsonResponse(dict, status: status)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func sendJSONArray(_ array: [[String: Any]], connection: NWConnection) {
        let response = DebugHTTP.jsonArrayResponse(array)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func sendRaw(data: Data, contentType: String, connection: NWConnection) {
        let response = DebugHTTP.rawResponse(data: data, contentType: contentType)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
#endif
