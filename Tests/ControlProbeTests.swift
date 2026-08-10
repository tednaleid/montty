// ABOUTME: Verifies the startup probe calls a socket taken only when a live
// ABOUTME: montty answers on it, and never blocks launch on a peer that stalls.

import Foundation
import Testing

/// A unix listener under a short path. `sun_path` holds 104 bytes and the
/// harness temporary directory is long enough on its own to crowd it, so these
/// live directly under `/tmp`.
private final class FakeServer {
    enum Behavior {
        /// Answers the way a running montty answers a ping.
        case montty
        /// Accepts and holds the connection open without ever writing.
        case silent
        /// Answers with bytes that are not a montty reply.
        case garbage
    }

    let socketPath: String
    private let directory: URL
    private var listener: Int32 = -1
    private let lock = NSLock()
    private var openClients: [Int32] = []
    private var received: [Data] = []

    init(behavior: Behavior) {
        directory = URL(fileURLWithPath: "/tmp/mtyprobe-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        socketPath = directory.appendingPathComponent("s").path

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = ControlTransport.address(for: socketPath)
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(listener, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        #expect(listen(listener, 8) == 0)

        DispatchQueue.global().async { [self] in acceptLoop(behavior) }
    }

    /// The bytes each connection sent before the server answered.
    func requests() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func stop() {
        lock.lock()
        let clients = openClients
        openClients = []
        lock.unlock()
        for client in clients { close(client) }
        if listener >= 0 { close(listener) }
        listener = -1
        try? FileManager.default.removeItem(at: directory)
    }

    /// Leaves the socket file on disk with nothing listening, the shape a crash
    /// leaves behind.
    func abandonSocketFile() {
        if listener >= 0 { close(listener) }
        listener = -1
    }

    private func acceptLoop(_ behavior: Behavior) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            var enabled: Int32 = 1
            setsockopt(
                client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)
            )
            if case .silent = behavior {
                lock.lock()
                openClients.append(client)
                lock.unlock()
                continue
            }
            if case .request(let data) = ControlTransport.readRequest(from: client) {
                lock.lock()
                received.append(data)
                lock.unlock()
            }
            answer(behavior).withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
            close(client)
        }
    }

    private func answer(_ behavior: Behavior) -> Data {
        switch behavior {
        case .montty: return (try? ControlResponse.ok.encoded()) ?? Data()
        case .garbage: return Data("HTTP/1.1 200 OK\r\n\r\n".utf8)
        case .silent: return Data()
        }
    }
}

@Suite struct ControlProbeTests {
    @Test func reportsLiveWhenAMonttyAnswersTheSocket() {
        let server = FakeServer(behavior: .montty)
        defer { server.stop() }

        #expect(ControlProbe.probe(socketPath: server.socketPath) == .live)
        #expect(server.requests().count == 1)
        #expect(server.requests().allSatisfy(ControlPing.isRequest))
    }

    @Test func reportsFreeWhenNoSocketExists() {
        let server = FakeServer(behavior: .montty)
        server.stop()

        #expect(ControlProbe.probe(socketPath: server.socketPath) == .free)
    }

    @Test func reportsFreeForASocketFileLeftBehindByACrash() {
        let server = FakeServer(behavior: .montty)
        defer { server.stop() }
        server.abandonSocketFile()

        #expect(FileManager.default.fileExists(atPath: server.socketPath))
        #expect(ControlProbe.probe(socketPath: server.socketPath) == .free)
    }

    @Test func reportsFreeInsideItsTimeoutWhenThePeerNeverAnswers() {
        let server = FakeServer(behavior: .silent)
        defer { server.stop() }

        let started = DispatchTime.now().uptimeNanoseconds
        let outcome = ControlProbe.probe(socketPath: server.socketPath, timeout: 0.25)
        let elapsed = DispatchTime.now().uptimeNanoseconds - started

        #expect(outcome == .free)
        #expect(elapsed < 2_000_000_000)
    }

    @Test func reportsFreeWhenTheAnswerIsNotAMonttyReply() {
        let server = FakeServer(behavior: .garbage)
        defer { server.stop() }

        #expect(ControlProbe.probe(socketPath: server.socketPath) == .free)
    }
}
