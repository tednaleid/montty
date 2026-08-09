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
    }
}
