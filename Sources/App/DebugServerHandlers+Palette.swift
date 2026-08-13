// ABOUTME: Reports the tab palette montty derived from the Ghostty config,
// ABOUTME: for diagnosing why a tab color does not match the theme.
#if DEBUG
import AppKit
import GhosttyKit
import Network

extension DebugServer {
    static func handlePalette(connection: NWConnection) {
        guard let appDel = AppDelegate.shared(),
              let cfg = appDel.ghostty.config.config else {
            sendJSON(["error": "no config"], status: 500, connection: connection)
            return
        }

        var result: [String: Any] = [
            "tabPaletteCount": appDel.tabPalette.count,
            "configErrors": appDel.ghostty.config.errors
        ]

        // Try reading palette via C API
        var palette = ghostty_config_palette_s()
        let key = "palette"
        let paletteOk = ghostty_config_get(cfg, &palette, key, UInt(key.utf8.count))
        result["paletteApiSuccess"] = paletteOk

        if paletteOk {
            // Show first 16 ANSI colors
            let colors: [String] = withUnsafeBytes(of: palette.colors) { buf in
                let bound = buf.bindMemory(to: ghostty_config_color_s.self)
                return Array(bound.prefix(16)).map { color in
                    String(format: "#%02X%02X%02X", color.r, color.g, color.b)
                }
            }
            result["ansi16"] = colors
        }

        // Also show loaded tab palette colors
        let loaded = appDel.tabPalette.map { color -> String in
            guard let rgb = color.usingColorSpace(.sRGB) else { return "?" }
            return String(
                format: "#%02X%02X%02X",
                Int(rgb.redComponent * 255),
                Int(rgb.greenComponent * 255),
                Int(rgb.blueComponent * 255)
            )
        }
        result["loadedPalette"] = loaded

        sendJSON(result, connection: connection)
    }
}
#endif
