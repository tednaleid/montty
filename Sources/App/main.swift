// ABOUTME: Application entry point using pure AppKit lifecycle.
// ABOUTME: Creates the app delegate and starts the run loop.

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
