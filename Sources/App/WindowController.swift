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
        window.delegate = self
        // This controller, not AppKit, owns the window's lifetime -- it stays
        // alive in AppDelegate.controllers past the close, so AppKit must not
        // also release its own retain when the window closes.
        window.isReleasedWhenClosed = false
        syncTitle()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    /// The window takes its name from the tab in front, so two windows are
    /// distinguishable in the Window menu and in Mission Control.
    func syncTitle() {
        let name = model.tabStore.activeTab?.displayName ?? ""
        window.title = name.isEmpty ? "Montty" : name
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appDelegate?.registry.keyWindowID = model.id
        syncTitle()
        appDelegate?.windowDidBecomeKey(self)
    }

    func windowDidResignKey(_ notification: Notification) {
        appDelegate?.windowDidResignKey()
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.windowWillClose(self)
    }
}
