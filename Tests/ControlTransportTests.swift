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

    @Test func readsARequestLargerThanTheKernelSocketBuffer() throws {
        let (client, server) = socketPair()
        defer { close(client); close(server) }

        let name = String(repeating: "n", count: 40_000)
        let request = ControlRequest(surface: "M1", command: .setName(name))
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
