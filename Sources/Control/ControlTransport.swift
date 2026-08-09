// ABOUTME: Framing for the control socket: reading one whole JSON request off a
// ABOUTME: stream, and telling a busy listener apart from an absent one.

import Foundation

enum ControlTransport {
    /// Largest request the server accepts. A request is a small JSON object,
    /// so the ceiling only bounds what a client that never stops writing can
    /// make a handler thread accumulate.
    static let maxRequestBytes = 1 << 20

    enum ReadOutcome: Equatable {
        case request(Data)
        case tooLarge
        case empty
    }

    /// Reads until the accumulated bytes form a complete JSON object. The
    /// kernel hands a large request over in several pieces, so treating the
    /// first read as the whole request decodes a prefix and calls a well
    /// formed request malformed. Bytes that never complete come back as they
    /// arrived, once the peer closes or the descriptor's receive timeout
    /// fires, so the caller still answers with a decode error rather than
    /// holding the connection open.
    static func readRequest(from descriptor: Int32) -> ReadOutcome {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[..<count])
            if data.count > maxRequestBytes { return .tooLarge }
            if isComplete(data) { return .request(data) }
        }
        return data.isEmpty ? .empty : .request(data)
    }

    /// One request is one JSON object, so parseability is the frame boundary.
    private static func isComplete(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

/// Why a control round trip never reached montty. All three exit the same way;
/// the message is what tells a caller whether retrying can help.
enum ControlTransportError: Error, Equatable {
    case notRunning
    case busy
    case disconnected

    var message: String {
        switch self {
        case .notRunning: return "montty is not running"
        case .busy: return "montty is busy and refused the connection, try again"
        case .disconnected: return "montty closed the connection before the request was sent"
        }
    }

    /// A refused connect to a socket that exists means montty is listening but
    /// its accept backlog is full, which a retry clears. A refusal with no
    /// socket on disk means no montty is running at all.
    static func forFailedConnect(code: Int32, socketExists: Bool) -> ControlTransportError {
        socketExists && (code == ECONNREFUSED || code == EAGAIN) ? .busy : .notRunning
    }
}
