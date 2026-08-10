// ABOUTME: Application entry point using pure AppKit lifecycle.
// ABOUTME: Creates the app delegate and starts the run loop.

import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
if ControlArgs.isInvocation(arguments) {
    ControlCLI.run(arguments: arguments)
}

// Ahead of the delegate: launching binds the hook socket and loads the session,
// and both belong to a montty that is already running.
InstanceGuard.exitIfAnotherMonttyServes(HookServer.socketPath)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
