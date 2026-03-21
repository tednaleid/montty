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
    private static func handleSurfaces(connection: NWConnection) {
        DispatchQueue.main.async {
            let surfaces = findSurfaces().map { view -> [String: Any] in
                var entry: [String: Any] = [
                    "id": view.id.uuidString,
                    "title": view.title,
                    "focused": view.focused
                ]
                if let pwd = view.pwd {
                    entry["pwd"] = pwd
                }
                if let size = view.surfaceSize {
                    entry["size"] = [
                        "rows": size.rows,
                        "cols": size.columns,
                        "width_px": size.width_px,
                        "height_px": size.height_px
                    ]
                }
                return entry
            }
            sendJSONArray(surfaces, connection: connection)
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

            // Map key names to the action string format Ghostty understands
            let action = keyActionString(for: keyName)
            if ghostty_surface_binding_action(surface, action, UInt(action.utf8.count)) {
                sendJSON(["ok": true, "key": keyName], connection: connection)
            } else {
                // For simple keys like "return", send as text
                if let text = keyToText(keyName) {
                    ghostty_surface_text(surface, text, UInt(text.utf8.count))
                    sendJSON(["ok": true, "key": keyName, "sent_as": "text"], connection: connection)
                } else {
                    sendJSON(["error": "Unknown key: \(keyName)"], status: 400, connection: connection)
                }
            }
        }
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
            guard let view = surface(forID: surfaceID) else {
                sendJSON(["error": "No surface found"], status: 404, connection: connection)
                return
            }
            guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                sendJSON(["error": "Failed to create bitmap"], status: 500, connection: connection)
                return
            }
            view.cacheDisplay(in: view.bounds, to: bitmapRep)
            guard let png = bitmapRep.representation(using: .png, properties: [:]) else {
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
