// ABOUTME: Owns one NSWindow and the WindowModel behind it, and is that
// ABOUTME: window's NSWindowDelegate, forwarding key-state changes to AppDelegate.

import AppKit
import SwiftUI

final class WindowController: NSObject, NSWindowDelegate {
    let model: WindowModel
    let window: NSWindow
    private weak var appDelegate: AppDelegate?

    init(model: WindowModel, ghostty: Ghostty.App, appDelegate: AppDelegate) {
        self.model = model
        self.appDelegate = appDelegate
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.contentView = NSHostingView(rootView:
            MainWindow(window: model)
                .environmentObject(ghostty)
                .environmentObject(appDelegate)
        )
        window.title = "Montty"
        window.delegate = self
        // This controller, not AppKit, owns the window's lifetime -- it stays
        // alive in AppDelegate.controllers past the close, so AppKit must not
        // also release its own retain when the window closes.
        window.isReleasedWhenClosed = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appDelegate?.registry.keyWindowID = model.id
        appDelegate?.windowDidBecomeKey(notification)
    }

    func windowDidResignKey(_ notification: Notification) {
        appDelegate?.windowDidResignKey(notification)
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.windowWillClose(self)
    }
}
