// ABOUTME: Wire plumbing for the control socket: one client round trip, reading
// ABOUTME: one whole JSON request off a stream, and explaining a failed connect.

import Foundation

enum ControlTransport {
    /// Largest request the server accepts. A request is a small JSON object,
    /// so the ceiling only bounds what a client that never stops writing can
    /// make a handler thread accumulate.
    static let maxRequestBytes = 1 << 20

    /// Longest the whole request read may take. A descriptor's receive timeout
    /// bounds one `read`, which a peer that trickles a byte at a time resets
    /// forever, so the total is what actually frees the handler thread. Two
    /// seconds is far longer than a request of any accepted size needs over a
    /// local socket, and it keeps the answer inside the client's 3s receive
    /// timeout.
    static let readDeadlineNanoseconds: UInt64 = 2_000_000_000

    enum ReadOutcome: Equatable {
        case request(Data)
        case tooLarge
        case empty
    }

    /// Reads until the accumulated bytes form a complete JSON object. The
    /// kernel hands a large request over in several pieces, so treating the
    /// first read as the whole request decodes a prefix and calls a well
    /// formed request malformed. Bytes that never complete come back as they
    /// arrived, once the peer closes, the descriptor's receive timeout fires,
    /// or the deadline passes, so the caller still answers with a decode error
    /// rather than holding the connection open.
    static func readRequest(
        from descriptor: Int32,
        deadlineNanoseconds: UInt64 = readDeadlineNanoseconds
    ) -> ReadOutcome {
        // Monotonic, so a clock adjustment mid-read cannot extend or collapse
        // the deadline.
        let deadline = DispatchTime.now().uptimeNanoseconds + deadlineNanoseconds
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[..<count])
            if data.count > maxRequestBytes { return .tooLarge }
            if isComplete(data) { return .request(data) }
            if DispatchTime.now().uptimeNanoseconds >= deadline { break }
        }
        return data.isEmpty ? .empty : .request(data)
    }

    /// One request is one JSON object, so parseability is the frame boundary.
    private static func isComplete(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// A missing or wedged socket should fail fast, so the send side keeps a
    /// tight timeout. The receive side has to outlast the server's own 2s
    /// main-thread ceiling, or a montty that is merely busy -- and about to
    /// reply with its own timeout error -- reads as "not running" instead.
    static let sendTimeout: TimeInterval = 1
    static let receiveTimeout: TimeInterval = 3

    /// Connects to `socketPath`, sends `payload`, and reads the reply until
    /// the peer closes. `receiveTimeout` bounds one read and the read as a
    /// whole, so a peer that answers a byte at a time cannot hold the caller
    /// past it.
    static func roundTrip(
        _ payload: Data,
        socketPath: String,
        expectReply: Bool,
        sendTimeout: TimeInterval = ControlTransport.sendTimeout,
        receiveTimeout: TimeInterval = ControlTransport.receiveTimeout
    ) -> Result<Data, ControlTransportError> {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { return .failure(.notRunning) }
        defer { close(sock) }

        // A peer that closes mid-write has to surface as a short write. The
        // CLI ignores SIGPIPE process-wide, but the app's startup probe runs
        // before any handler of its own is installed.
        var noSignal: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var send = interval(sendTimeout)
        var receive = interval(receiveTimeout)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &send, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &receive, socklen_t(MemoryLayout<timeval>.size))

        var addr = address(for: socketPath)

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return .failure(.forFailedConnect(
                code: errno,
                socketExists: FileManager.default.fileExists(atPath: socketPath)
            ))
        }

        var sent = 0
        payload.withUnsafeBytes { raw in
            while sent < raw.count {
                let written = write(sock, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if written <= 0 { break }
                sent += written
            }
        }
        guard sent == payload.count else { return .failure(.disconnected) }
        guard expectReply else { return .success(Data()) }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(receiveTimeout * 1_000_000_000)
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(sock, &buffer, buffer.count)
            if count <= 0 { break }
            reply.append(contentsOf: buffer[..<count])
            if DispatchTime.now().uptimeNanoseconds >= deadline { break }
        }
        return .success(reply)
    }

    /// Fills a `sockaddr_un` for `socketPath`. `sun_path` holds 104 bytes on
    /// macOS, so a longer path is truncated and names a different socket.
    static func address(for socketPath: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr) { addrPtr in
                let pathPtr = UnsafeMutableRawPointer(addrPtr)
                    .advanced(by: MemoryLayout.offset(of: \sockaddr_un.sun_path)!)
                    .assumingMemoryBound(to: CChar.self)
                _ = strlcpy(pathPtr, src, 104)
            }
        }
        return addr
    }

    private static func interval(_ seconds: TimeInterval) -> timeval {
        timeval(
            tv_sec: Int(seconds),
            tv_usec: __darwin_suseconds_t((seconds - seconds.rounded(.down)) * 1_000_000)
        )
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
