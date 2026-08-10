// ABOUTME: Asks whether a live montty already serves a control socket, so a
// ABOUTME: second launch never takes over the first one's socket and session.

import Foundation

enum ControlProbe {
    /// What the probe found. Only a montty that answers counts as `live`:
    /// concluding `live` wrongly refuses to launch the app at all, while
    /// concluding `free` wrongly leaves the behavior that had no guard.
    enum Outcome: Equatable {
        /// A montty answered the ping. The socket and the session it names
        /// belong to that process.
        case live
        /// Nothing answered as montty: no socket file, a file a crash left
        /// behind, another program on the path, or a peer too slow to answer.
        case free
    }

    /// Orders of magnitude longer than a local round trip needs, and short
    /// enough that a wedged peer cannot noticeably delay launch. A montty
    /// answers a ping from the connection's own thread, so a busy main thread
    /// does not spend this budget.
    static let timeout: TimeInterval = 1

    /// Requires positive proof, so every way the round trip can fall short --
    /// a refused connect, a peer that says nothing, an answer that is not
    /// montty's -- comes back `free`.
    static func probe(
        socketPath: String, timeout: TimeInterval = ControlProbe.timeout
    ) -> Outcome {
        let outcome = ControlTransport.roundTrip(
            ControlPing.request,
            socketPath: socketPath,
            expectReply: true,
            sendTimeout: timeout,
            receiveTimeout: timeout
        )
        guard case .success(let reply) = outcome, ControlPing.isReply(reply) else {
            return .free
        }
        return .live
    }
}
