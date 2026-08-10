// ABOUTME: Activity state for a terminal pane, populated by hook events
// ABOUTME: routed by MONTTY_SURFACE_ID.

import Foundation

struct ActivityStatus: Equatable {
    let sessionName: String
    let state: State

    enum State: Equatable {
        case working    // actively processing (hook: prompt-submit, pre-tool-use)
        case waiting    // needs user input (hook: notification)
        case idle       // session present, not actively working (hook: session-start, stop)

        /// The name this state travels under on the control socket and in the
        /// debug server payloads. Spelled out so renaming a case is a compile
        /// error here rather than a silent change to the public protocol.
        var wireName: String {
            switch self {
            case .working: return "working"
            case .waiting: return "waiting"
            case .idle: return "idle"
            }
        }
    }
}
