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
        let all = findSurfaces()
        if let id = id, let uuid = UUID(uuidString: id) {
            return all.first { $0.id == uuid }
        }
        // Return focused surface, or first if none focused
        return all.first { $0.focused } ?? all.first
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
                for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                    var entry: [String: Any] = [
                        "id": leaf.surfaceID.uuidString,
                        "leaf_id": leaf.id.uuidString,
                        "tab_id": tab.id.uuidString,
                        "tab_name": tab.displayName,
                        "tab_position": tab.position,
                        "tab_color": colorString(tab.color),
                        "active": isActiveTab,
                        "focused_in_tab": leaf.id == tab.focusedLeafID
                    ]
                    if let view = appDelegate.surfaceView(for: leaf.surfaceID) {
                        entry["title"] = view.title
                        if let size = view.surfaceSize {
                            entry["size"] = [
                                "rows": size.rows,
                                "cols": size.columns,
                                "width_px": size.width_px,
                                "height_px": size.height_px
                            ]
                        }
                    }
                    if let pwd = tab.workingDirectory {
                        entry["pwd"] = pwd
                    }
                    results.append(entry)
                }
            }
            sendJSONArray(results, connection: connection)
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

            // Send as a proper key event via ghostty_surface_key
            if let keyEvent = buildKeyEvent(for: keyName) {
                // Press
                ghostty_surface_key(surface, keyEvent)
                // Release
                var release = keyEvent
                release.action = GHOSTTY_ACTION_RELEASE
                ghostty_surface_key(surface, release)
                sendJSON(["ok": true, "key": keyName], connection: connection)
            } else {
                sendJSON(
                    ["error": "Unknown key: \(keyName)"],
                    status: 400,
                    connection: connection
                )
            }
        }
    }

    // Build a ghostty_input_key_s for a named key, with optional modifiers.
    // swiftlint:disable:next cyclomatic_complexity
    private static func buildKeyEvent(for name: String) -> ghostty_input_key_s? {
        let lower = name.lowercased()
        var mods = ghostty_input_mods_e(rawValue: 0)
        var keyName = lower

        // Parse modifier prefix (e.g., "ctrl+c")
        if lower.hasPrefix("ctrl+") {
            mods = GHOSTTY_MODS_CTRL
            keyName = String(lower.dropFirst(5))
        }

        let key: ghostty_input_key_e
        let text: String?
        switch keyName {
        case "return", "enter":    key = GHOSTTY_KEY_ENTER;     text = "\r"
        case "tab":                key = GHOSTTY_KEY_TAB;       text = "\t"
        case "space":              key = GHOSTTY_KEY_SPACE;     text = " "
        case "escape", "esc":      key = GHOSTTY_KEY_ESCAPE;    text = nil
        case "backspace", "delete": key = GHOSTTY_KEY_BACKSPACE; text = nil
        case "up":                 key = GHOSTTY_KEY_ARROW_UP;    text = nil
        case "down":               key = GHOSTTY_KEY_ARROW_DOWN;  text = nil
        case "left":               key = GHOSTTY_KEY_ARROW_LEFT;  text = nil
        case "right":              key = GHOSTTY_KEY_ARROW_RIGHT; text = nil
        default:
            // Single character keys (a-z)
            if keyName.count == 1, let char = keyName.first, char.isLetter {
                key = letterToKey(char)
                if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 {
                    text = nil
                } else {
                    text = keyName
                }
            } else {
                return nil
            }
        }

        return withText(text) { textPtr in
            ghostty_input_key_s(
                action: GHOSTTY_ACTION_PRESS,
                mods: mods,
                consumed_mods: ghostty_input_mods_e(rawValue: 0),
                keycode: key.rawValue,
                text: textPtr,
                unshifted_codepoint: 0,
                composing: false
            )
        }
    }

    // Convert a lowercase letter to its GHOSTTY_KEY_* constant.
    private static func letterToKey(_ char: Character) -> ghostty_input_key_e {
        let offset = Int(char.asciiValue ?? 0) - Int(Character("a").asciiValue ?? 0)
        return ghostty_input_key_e(rawValue: GHOSTTY_KEY_A.rawValue + UInt32(offset))
    }

    // Call body with a C string pointer that lives for the duration.
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
