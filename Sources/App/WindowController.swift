// ABOUTME: Owns one NSWindow and the model state behind it, so the application
// ABOUTME: delegate no longer stands in for the single window it used to have.

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
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appDelegate?.registry.keyWindowID = model.id
    }

    func windowWillClose(_ notification: Notification) {
        appDelegate?.windowWillClose(self)
    }
}
