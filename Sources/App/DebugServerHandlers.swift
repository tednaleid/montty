// ABOUTME: Route handlers for DebugServer HTTP endpoints.
// ABOUTME: Handles /surfaces, /type, /key, /screen, /screenshot, /state, /action requests.
#if DEBUG
import AppKit
import GhosttyKit
import Network

extension DebugServer {
    // MARK: - Routing
    static func routeRequest(_ request: HTTPRequest, connection: NWConnection) {
        let surfaceID = request.query["surface"]

        switch (request.method, request.path) {
        case ("GET", "/surfaces"):
            handleSurfaces(connection: connection)
        case ("POST", "/type"):
            handleType(body: request.body, surfaceID: surfaceID, connection: connection)
        case ("POST", "/key"):
            handleKey(body: request.body, surfaceID: surfaceID, connection: connection)
        case ("GET", "/screen"):
            handleScreen(surfaceID: surfaceID, connection: connection)
        case ("GET", "/screenshot"):
            handleScreenshot(surfaceID: surfaceID, connection: connection)
        case ("GET", "/state"):
            handleState(surfaceID: surfaceID, connection: connection)
        case ("POST", "/action"):
            handleAction(body: request.body, surfaceID: surfaceID, connection: connection)
        default:
            sendJSON(["error": "Not found: \(request.method) \(request.path)"], status: 404, connection: connection)
        }
    }

    // MARK: - Surface discovery
    private static func findSurfaces() -> [Ghostty.SurfaceView] {
        var results: [Ghostty.SurfaceView] = []
        for window in NSApp?.windows ?? [] {
            findSurfacesIn(view: window.contentView, results: &results)
        }
        return results
    }

    private static func findSurfacesIn(view: NSView?, results: inout [Ghostty.SurfaceView]) {
        guard let view = view else { return }
        if let surfaceView = view as? Ghostty.SurfaceView {
            results.append(surfaceView)
            return
        }
        for subview in view.subviews {
            findSurfacesIn(view: subview, results: &results)
        }
    }

    /// Find a surface by UUID string, or return the focused/first surface.
    static func surface(forID id: String?) -> Ghostty.SurfaceView? {
        if let id = id, let uuid = UUID(uuidString: id) {
            return appDelegate()?.surfaceView(for: uuid)
                ?? findSurfaces().first { $0.id == uuid }
        }
        // Use the tab model's focused surface, not AppKit's
        if let appDel = appDelegate(),
           let tab = appDel.tabStore.activeTab,
           let surfaceID = tab.focusedSurfaceID {
            return appDel.surfaceView(for: surfaceID)
        }
        return findSurfaces().first
    }

    // MARK: - Handlers
    private static func appDelegate() -> AppDelegate? {
        // With @NSApplicationDelegateAdaptor, NSApp.delegate is a SwiftUI
        // wrapper. Walk its properties to find our actual AppDelegate.
        guard let delegate = NSApp?.delegate else { return nil }
        if let appDel = delegate as? AppDelegate { return appDel }
        // SwiftUI stores the adaptee in a property
        let mirror = Mirror(reflecting: delegate)
        for child in mirror.children {
            if let appDel = child.value as? AppDelegate { return appDel }
        }
        return nil
    }

    private static func handleSurfaces(connection: NWConnection) {
        DispatchQueue.main.async {
            guard let appDelegate = appDelegate() else {
                sendJSONArray([], connection: connection)
                return
            }
            var results: [[String: Any]] = []
            for tab in appDelegate.tabStore.tabs {
                let isActiveTab = tab.id == appDelegate.tabStore.activeTabID
                let info = tab.tabInfo
                for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                    var entry = surfaceEntry(
                        leaf: leaf, tab: tab, info: info,
                        isActiveTab: isActiveTab, appDelegate: appDelegate
                    )
                    addSurfaceViewData(leaf: leaf, appDelegate: appDelegate, entry: &entry)
                    results.append(entry)
                }
            }
            sendJSONArray(results, connection: connection)
        }
    }

    private static func surfaceEntry(
        leaf: SurfaceLeaf, tab: Tab, info: TabInfo,
        isActiveTab: Bool, appDelegate: AppDelegate
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "id": leaf.surfaceID.uuidString,
            "leaf_id": leaf.id.uuidString,
            "tab_id": tab.id.uuidString,
            "tab_name": info.displayName,
            "tab_position": tab.position,
            "tab_color": colorString(tab.color),
            "active": isActiveTab,
            "focused_in_tab": leaf.id == tab.focusedLeafID,
            "split_count": info.splitCount
        ]
        if let dirName = info.directoryName {
            entry["directory_name"] = dirName
        }
        if let gitInfo = info.gitInfo {
            var git: [String: Any] = [
                "repo_name": gitInfo.repoName,
                "repo_path": gitInfo.repoPath
            ]
            if let branch = gitInfo.branchName { git["branch"] = branch }
            if let worktree = gitInfo.worktreeName { git["worktree"] = worktree }
            entry["git"] = git
        }
        if let claude = info.claudeCode {
            entry["claude_code"] = [
                "session_name": claude.sessionName,
                "state": String(describing: claude.state)
            ]
        }
        return entry
    }

    private static func addSurfaceViewData(
        leaf: SurfaceLeaf, appDelegate: AppDelegate, entry: inout [String: Any]
    ) {
        guard let view = appDelegate.surfaceView(for: leaf.surfaceID) else { return }
        entry["title"] = view.title
        if let pwd = view.pwd { entry["pwd"] = pwd }
        if let size = view.surfaceSize {
            entry["size"] = [
                "rows": size.rows, "cols": size.columns,
                "width_px": size.width_px, "height_px": size.height_px
            ]
        }
    }

    private static func colorString(_ color: TabColor) -> String {
        switch color {
        case .preset(let preset): return preset.rawValue
        case .auto: return "auto"
        }
    }

    private static func handleType(body: String, surfaceID: String?, connection: NWConnection) {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            sendJSON(["error": "Empty body"], status: 400, connection: connection)
            return
        }

        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            guard let surface = view.surface else {
                sendJSON(["error": "Surface not initialized"], status: 500, connection: connection)
                return
            }
            ghostty_surface_text(surface, text, UInt(text.utf8.count))
            sendJSON(["ok": true, "typed": text], connection: connection)
        }
    }

    private static func handleKey(body: String, surfaceID: String?, connection: NWConnection) {
        let keyName = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyName.isEmpty else {
            sendJSON(["error": "Empty body"], status: 400, connection: connection)
            return
        }

        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            guard let surface = view.surface else {
                sendJSON(["error": "Surface not initialized"], status: 500, connection: connection)
                return
            }

            // Send as a proper key event via ghostty_surface_key.
            // Must call ghostty_surface_key inside the text scope
            // because the text pointer is only valid within withCString.
            sendKeyEvent(for: keyName, surface: surface, connection: connection)
        }
    }

    // Send a key event to the surface, keeping text pointer alive for the duration.
    // ghostty_surface_key expects macOS physical keycodes, not GHOSTTY_KEY_* enums.
    private static func sendKeyEvent(
        for name: String, surface: ghostty_surface_t, connection: NWConnection
    ) {
        let lower = name.lowercased()
        var mods = ghostty_input_mods_e(rawValue: 0)
        var keyName = lower

        // Parse modifier prefix (e.g., "ctrl+c")
        if lower.hasPrefix("ctrl+") {
            mods = GHOSTTY_MODS_CTRL
            keyName = String(lower.dropFirst(5))
        }

        guard let (keycode, text) = resolveKey(keyName, mods: mods) else {
            sendJSON(["error": "Unknown key: \(name)"], status: 400, connection: connection)
            return
        }

        // Call ghostty_surface_key INSIDE withCString so the text pointer is valid
        withText(text) { textPtr in
            var keyEvent = ghostty_input_key_s(
                action: GHOSTTY_ACTION_PRESS,
                mods: mods,
                consumed_mods: ghostty_input_mods_e(rawValue: 0),
                keycode: keycode,
                text: textPtr,
                unshifted_codepoint: 0,
                composing: false
            )
            ghostty_surface_key(surface, keyEvent)
            keyEvent.action = GHOSTTY_ACTION_RELEASE
            ghostty_surface_key(surface, keyEvent)
        }
        sendJSON(["ok": true, "key": name], connection: connection)
    }

    // Resolve a key name to its macOS physical keycode and text character.
    // swiftlint:disable:next cyclomatic_complexity
    private static func resolveKey(
        _ keyName: String, mods: ghostty_input_mods_e
    ) -> (keycode: UInt32, text: String?)? {
        switch keyName {
        case "return", "enter":     return (36, "\r")
        case "tab":                 return (48, "\t")
        case "space":               return (49, " ")
        case "escape", "esc":       return (53, nil)
        case "backspace", "delete": return (51, "\u{7f}")
        case "up":                  return (126, nil)
        case "down":                return (125, nil)
        case "left":                return (123, nil)
        case "right":               return (124, nil)
        default:
            if keyName.count == 1, let char = keyName.first, char.isLetter,
               let code = macOSKeycode(for: char) {
                let text = (mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0) ? nil : keyName
                return (code, text)
            }
            return nil
        }
    }

    // macOS physical keycodes for letter keys (ANSI layout).
    private static func macOSKeycode(for char: Character) -> UInt32? {
        // macOS keycodes are based on physical key position, not ASCII.
        let map: [Character: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6,
            "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
            "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34,
            "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46
        ]
        return map[char]
    }

    // Call body with a C string pointer that lives for the duration.
    @discardableResult
    private static func withText<T>(
        _ text: String?,
        body: (UnsafePointer<CChar>?) -> T
    ) -> T {
        if let text = text {
            return text.withCString { body($0) }
        }
        return body(nil)
    }

    private static func handleScreen(surfaceID: String?, connection: NWConnection) {
        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            guard let surface = view.surface else {
                sendJSON(["error": "Surface not initialized"], status: 500, connection: connection)
                return
            }
            // Read the entire visible viewport
            let topLeft = ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0, y: 0
            )
            let bottomRight = ghostty_point_s(
                tag: GHOSTTY_POINT_VIEWPORT,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0, y: 0
            )
            let sel = ghostty_selection_s(
                top_left: topLeft,
                bottom_right: bottomRight,
                rectangle: false
            )
            var text = ghostty_text_s()
            guard ghostty_surface_read_text(surface, sel, &text) else {
                sendJSON(["error": "Failed to read terminal text"], status: 500, connection: connection)
                return
            }
            defer { ghostty_surface_free_text(surface, &text) }

            let content = text.text != nil ? String(cString: text.text) : ""
            var result: [String: Any] = ["text": content]
            if let size = view.surfaceSize {
                result["rows"] = size.rows
                result["cols"] = size.columns
            }
            sendJSON(result, connection: connection)
        }
    }

    private static func handleScreenshot(surfaceID: String?, connection: NWConnection) {
        DispatchQueue.main.async {
            // Capture the full window (including sidebar and titlebar)
            guard let window = NSApp?.mainWindow
                    ?? NSApp?.keyWindow
                    ?? NSApp?.windows.first(where: { $0.isVisible }) else {
                sendJSON(["error": "No window found"], status: 404, connection: connection)
                return
            }
            let windowID = CGWindowID(window.windowNumber)
            guard let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming]
            ) else {
                sendJSON(["error": "Window capture failed"], status: 500, connection: connection)
                return
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                sendJSON(["error": "PNG conversion failed"], status: 500, connection: connection)
                return
            }
            sendRaw(data: png, contentType: "image/png", connection: connection)
        }
    }

    private static func handleState(surfaceID: String?, connection: NWConnection) {
        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            var state: [String: Any] = [
                "id": view.id.uuidString,
                "title": view.title,
                "focused": view.focused
            ]
            if let pwd = view.pwd {
                state["pwd"] = pwd
            }
            if let size = view.surfaceSize {
                state["size"] = [
                    "rows": size.rows,
                    "cols": size.columns,
                    "width_px": size.width_px,
                    "height_px": size.height_px
                ]
            }
            sendJSON(state, connection: connection)
        }
    }

    private static func handleAction(body: String, surfaceID: String?, connection: NWConnection) {
        let action = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            sendJSON(["error": "Empty body"], status: 400, connection: connection)
            return
        }

        DispatchQueue.main.async {
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            guard let surface = view.surface else {
                sendJSON(["error": "Surface not initialized"], status: 500, connection: connection)
                return
            }
            let result = ghostty_surface_binding_action(surface, action, UInt(action.utf8.count))
            sendJSON(["ok": result, "action": action], connection: connection)
        }
    }

}
#endif
