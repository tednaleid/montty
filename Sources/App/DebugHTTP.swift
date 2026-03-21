// ABOUTME: HTTP response building helpers for DebugServer.
// ABOUTME: Constructs HTTP/1.1 response data for JSON, JSON arrays, and raw payloads.

#if DEBUG

import Foundation

enum DebugHTTP {
    static func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default:  return "Error"
        }
    }

    static func httpHeader(status: Int, contentType: String, contentLength: Int) -> String {
        "HTTP/1.1 \(status) \(statusText(for: status))\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(contentLength)\r\n"
            + "Connection: close\r\n\r\n"
    }

    static func jsonResponse(_ dict: [String: Any], status: Int = 200) -> Data {
        let json = (try? JSONSerialization.data(
            withJSONObject: dict, options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        let header = httpHeader(
            status: status, contentType: "application/json",
            contentLength: json.count
        )
        return Data(header.utf8) + json
    }

    static func jsonArrayResponse(_ array: [[String: Any]]) -> Data {
        let json = (try? JSONSerialization.data(
            withJSONObject: array, options: [.sortedKeys]
        )) ?? Data("[]".utf8)
        let header = httpHeader(
            status: 200, contentType: "application/json",
            contentLength: json.count
        )
        return Data(header.utf8) + json
    }

    static func rawResponse(data: Data, contentType: String) -> Data {
        let header = httpHeader(
            status: 200, contentType: contentType,
            contentLength: data.count
        )
        return Data(header.utf8) + data
    }
}

#endif
