// ABOUTME: Builds the main menu bar with File and Window menus.
// ABOUTME: Reads keybindings from Ghostty config for shortcut display.

import AppKit
import GhosttyKit
import SwiftUI

enum MenuBuilder {
    /// Build and install the main menu bar.
    static func buildMainMenu(
        config: Ghostty.Config, appDelegate: AppDelegate
    ) {
        let mainMenu = NSMenu()

        // App menu (Montty)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About Montty",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Montty",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let ctx = MenuContext(config: config, appDelegate: appDelegate)
        mainMenu.addItem(buildFileMenu(ctx))

        // Edit menu (standard)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window menu
        mainMenu.addItem(buildWindowMenu(ctx))

        NSApp.mainMenu = mainMenu
    }

    /// Bundles config + appDelegate to reduce parameter passing.
    private struct MenuContext {
        let config: Ghostty.Config
        let appDelegate: AppDelegate
    }

    // MARK: - File menu

    private static func buildFileMenu(_ ctx: MenuContext) -> NSMenuItem {
        let menu = NSMenu(title: "File")

        addAction(to: menu, title: "New Tab", action: "new_tab", ctx: ctx)
        menu.addItem(.separator())
        addAction(to: menu, title: "New Split Right", action: "new_split:right", ctx: ctx)
        addAction(to: menu, title: "New Split Down", action: "new_split:down", ctx: ctx)
        addAction(to: menu, title: "New Split Left", action: "new_split:left", ctx: ctx)
        addAction(to: menu, title: "New Split Up", action: "new_split:up", ctx: ctx)
        menu.addItem(.separator())
        addAction(to: menu, title: "Close Split", action: "close_surface", ctx: ctx)
        addAction(to: menu, title: "Close Tab", action: "close_tab", ctx: ctx)
        menu.addItem(.separator())
        addItem(to: menu, title: "Open Config", key: ",", mods: [.command]) {
            ctx.appDelegate.openConfig()
        }

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Window menu

    private static func buildWindowMenu(_ ctx: MenuContext) -> NSMenuItem {
        let menu = NSMenu(title: "Window")

        // Select split
        let selectMenu = NSMenu(title: "Select Split")
        addAction(to: selectMenu, title: "Previous", action: "goto_split:previous", ctx: ctx)
        addAction(to: selectMenu, title: "Next", action: "goto_split:next", ctx: ctx)
        selectMenu.addItem(.separator())
        addAction(to: selectMenu, title: "Left", action: "goto_split:left", ctx: ctx)
        addAction(to: selectMenu, title: "Right", action: "goto_split:right", ctx: ctx)
        addAction(to: selectMenu, title: "Up", action: "goto_split:top", ctx: ctx)
        addAction(to: selectMenu, title: "Down", action: "goto_split:bottom", ctx: ctx)
        let selectItem = NSMenuItem(title: "Select Split", action: nil, keyEquivalent: "")
        selectItem.submenu = selectMenu
        menu.addItem(selectItem)

        // Resize split
        let resizeMenu = NSMenu(title: "Resize Split")
        addAction(to: resizeMenu, title: "Left", action: "resize_split:left,10", ctx: ctx)
        addAction(to: resizeMenu, title: "Right", action: "resize_split:right,10", ctx: ctx)
        addAction(to: resizeMenu, title: "Up", action: "resize_split:up,10", ctx: ctx)
        addAction(to: resizeMenu, title: "Down", action: "resize_split:down,10", ctx: ctx)
        let resizeItem = NSMenuItem(title: "Resize Split", action: nil, keyEquivalent: "")
        resizeItem.submenu = resizeMenu
        menu.addItem(resizeItem)

        menu.addItem(.separator())
        addAction(to: menu, title: "Equalize Splits", action: "equalize_splits", ctx: ctx)
        addAction(to: menu, title: "Toggle Zoom", action: "toggle_split_zoom", ctx: ctx)
        menu.addItem(.separator())
        addAction(to: menu, title: "Toggle Fullscreen", action: "toggle_fullscreen", ctx: ctx)

        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    // MARK: - Helpers

    /// Add a menu item that triggers a Ghostty binding action.
    private static func addAction(
        to menu: NSMenu, title: String, action ghosttyAction: String,
        ctx: MenuContext
    ) {
        let shortcut = triggerForMenu(action: ghosttyAction, config: ctx.config)
        let item = NSMenuItem(
            title: title,
            action: #selector(AppDelegate.handleMenuAction(_:)),
            keyEquivalent: shortcut?.keyEquivalent ?? ""
        )
        if let mods = shortcut?.modifiers {
            item.keyEquivalentModifierMask = mods
        }
        item.representedObject = ghosttyAction
        item.target = ctx.appDelegate
        menu.addItem(item)
    }

    /// Add a menu item with a custom closure action.
    private static func addItem(
        to menu: NSMenu, title: String, key: String,
        mods: NSEvent.ModifierFlags, handler: @escaping () -> Void
    ) {
        let item = ClosureMenuItem(
            title: title, keyEquivalent: key, handler: handler)
        item.keyEquivalentModifierMask = mods
        menu.addItem(item)
    }

    /// Look up the trigger for a Ghostty action.
    private static func triggerForMenu(
        action: String, config: Ghostty.Config
    ) -> (keyEquivalent: String, modifiers: NSEvent.ModifierFlags)? {
        guard let cfg = config.config else { return nil }
        let trigger = ghostty_config_trigger(
            cfg, action, UInt(action.utf8.count))

        switch trigger.tag {
        case GHOSTTY_TRIGGER_UNICODE:
            guard let scalar = UnicodeScalar(trigger.key.unicode)
            else { return nil }
            let mods = Ghostty.eventModifierFlags(mods: trigger.mods)
            return (String(Character(scalar)), mods)

        case GHOSTTY_TRIGGER_PHYSICAL:
            if let shortcut = Ghostty.keyboardShortcut(for: trigger) {
                let mods = Ghostty.eventModifierFlags(mods: trigger.mods)
                return (String(shortcut.key.character), mods)
            }
            return nil

        default:
            return nil
        }
    }
}

/// NSMenuItem subclass that calls a closure when triggered.
private class ClosureMenuItem: NSMenuItem {
    let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(
            title: title, action: #selector(invoke),
            keyEquivalent: keyEquivalent)
        self.target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    @objc private func invoke() {
        handler()
    }
}
