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

        /// How much a state wants the user's attention; higher wants more. A
        /// session that is waiting on a question comes first, a finished one
        /// waiting on its next prompt second, and one still busy last, since
        /// it needs nothing from the user yet.
        private var urgency: Int {
            switch self {
            case .waiting: return 2
            case .idle: return 1
            case .working: return 0
            }
        }

        /// The state of a group of panes that wants the user most: waiting,
        /// then idle, then working. Nil for no panes at all.
        static func mostUrgent(of states: [State]) -> State? {
            states.max { $0.urgency < $1.urgency }
        }

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
