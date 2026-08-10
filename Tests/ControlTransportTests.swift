// ABOUTME: Verifies the control socket assembles one whole request from a
// ABOUTME: stream that delivers it in pieces, and explains a failed connect.

import Foundation
import Testing

@Suite struct ControlTransportTests {
    /// A connected pair of unix stream sockets, the shape the CLI and the app
    /// share. Neither end raises SIGPIPE, so a test that stops reading cannot
    /// kill the test runner.
    private func socketPair() -> (client: Int32, server: Int32) {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        for descriptor in pair {
            var enabled: Int32 = 1
            setsockopt(
                descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)
            )
        }
        return (pair[0], pair[1])
    }

    private func writeInBackground(_ data: Data, to descriptor: Int32) {
        DispatchQueue.global().async {
            data.withUnsafeBytes { raw in
                var sent = 0
                while sent < raw.count {
                    let written = write(descriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                    if written <= 0 { break }
                    sent += written
                }
            }
        }
    }

    /// Writes `data` one byte at a time with a pause between bytes, the shape
    /// of a client that keeps a connection alive without ever completing a
    /// request. The returned semaphore signals once the writer is done.
    private func trickle(
        _ data: Data, to descriptor: Int32, microsecondsPerByte: UInt32
    ) -> DispatchSemaphore {
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            for byte in data {
                var copy = byte
                if write(descriptor, &copy, 1) != 1 { break }
                usleep(microsecondsPerByte)
            }
            finished.signal()
        }
        return finished
    }

    @Test func readsARequestLargerThanTheKernelSocketBuffer() throws {
        let (client, server) = socketPair()
        defer { close(client); close(server) }

        let surface = String(repeating: "M", count: 40_000)
        let request = ControlRequest(surface: surface, command: .info)
        let payload = try request.encoded()
        #expect(payload.count > 8192)
        writeInBackground(payload, to: client)

        guard case .request(let data) = ControlTransport.readRequest(from: server) else {
            Issue.record("expected a complete request")
            return
        }
        #expect(try ControlRequest.decode(data) == request)
    }

    @Test func stopsAtTheRequestCeiling() {
        let (client, server) = socketPair()
        defer { close(client); close(server) }

        let oversized = Data(
            repeating: UInt8(ascii: "{"), count: ControlTransport.maxRequestBytes + 8192
        )
        writeInBackground(oversized, to: client)

        #expect(ControlTransport.readRequest(from: server) == .tooLarge)
    }

    @Test func reportsNothingWhenThePeerClosesWithoutWriting() {
        let (client, server) = socketPair()
        defer { close(server) }
        close(client)

        #expect(ControlTransport.readRequest(from: server) == .empty)
    }

    @Test func returnsWhatArrivedWhenThePeerClosesMidRequest() {
        let (client, server) = socketPair()
        defer { close(server) }

        let partial = Data(#"{"v":1,"cmd":"set""#.utf8)
        partial.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
        close(client)

        #expect(ControlTransport.readRequest(from: server) == .request(partial))
    }

    @Test func stopsWhenTheDeadlineForTheWholeRequestPasses() throws {
        let (client, server) = socketPair()
        defer { close(client); close(server) }

        let payload = try ControlRequest(surface: "M1", command: .setName("trickled")).encoded()
        let finished = trickle(payload, to: client, microsecondsPerByte: 5_000)

        let started = DispatchTime.now().uptimeNanoseconds
        let outcome = ControlTransport.readRequest(from: server, deadlineNanoseconds: 50_000_000)
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        finished.wait()

        guard case .request(let data) = outcome else {
            Issue.record("expected the bytes that arrived before the deadline")
            return
        }
        #expect(data.count < payload.count)
        #expect(elapsed < 250_000_000)
    }

    @Test func aPeerThatSendsNothingIsBoundedByTheReceiveTimeout() {
        let (client, server) = socketPair()
        defer { close(client); close(server) }

        var timeout = timeval(tv_sec: 0, tv_usec: 50_000)
        setsockopt(server, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        #expect(ControlTransport.readRequest(from: server) == .empty)
    }

    @Test func aRefusedConnectToAnExistingSocketMeansBusyRatherThanMissing() {
        #expect(ControlTransportError.forFailedConnect(
            code: ECONNREFUSED, socketExists: true
        ) == .busy)
        #expect(ControlTransportError.forFailedConnect(
            code: ECONNREFUSED, socketExists: false
        ) == .notRunning)
        #expect(ControlTransportError.forFailedConnect(
            code: ENOENT, socketExists: false
        ) == .notRunning)
        #expect(!ControlTransportError.busy.message.contains("not running"))
    }
}
