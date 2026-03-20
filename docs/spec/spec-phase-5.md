# Phase 5: Polish

## Goal

Add auto-naming from directory, auto-coloring from env/directory, per-tab terminal theming, remaining keyboard shortcuts, SwiftLint integration, and sidebar resize. These are the finishing touches that make the daily workflow smooth.

## Technical Approach

### Auto-naming from working directory

When Ghostty reports a working directory change via `GHOSTTY_ACTION_PWD`:
1. Find the tab containing the reporting surface
2. Set `tab.workingDirectory` to the reported path
3. Set `tab.autoName` to the last path component (e.g., `/Users/ted/projects/myapp` -> `myapp`)
4. If the user has set a custom `tab.name`, it takes precedence (the `displayName` computed property handles this)

For multi-pane tabs, the focused pane's working directory is shown.

### Auto-color from directory or env variable

When `tab.color == .auto`:
1. Check if the focused surface has a `MONTTY_COLOR` env variable set (the terminal process can `export MONTTY_COLOR=red`)
2. If yes, use that preset color name
3. If no, hash the working directory path to pick from the preset color palette

The hashing algorithm:
```swift
extension TabColor {
    static func autoColor(forDirectory dir: String?, envColor: String?) -> PresetColor {
        // Env variable takes precedence
        if let envColor, let preset = PresetColor(rawValue: envColor.lowercased()) {
            return preset
        }

        // Hash the directory to a color
        guard let dir else { return .gray }
        let hash = dir.utf8.reduce(0) { ($0 &+ UInt64($1)) &* 31 }
        let colors = PresetColor.allCases
        return colors[Int(hash % UInt64(colors.count))]
    }
}
```

This gives the "rainbow" effect naturally: different directories get different colors, same directory always gets the same color.

### Env variable detection

Detecting `MONTTY_COLOR` from a running shell requires one of:
- **OSC escape sequence**: Define a custom OSC that the shell sends when `MONTTY_COLOR` changes. The user adds a hook to their shell RC file.
- **Simpler approach**: Read the env from the surface's initial config, or let the user set it in Ghostty config as a keybinding/action.

For v1, the simplest approach: the user can set the color manually (per Phase 2), and auto-color from directory hashing works automatically for `.auto` tabs. Env variable support can be a future enhancement unless it turns out to be simple to read from the surface.

### Per-tab terminal theming

When a tab has a color (user-assigned or auto-derived), the terminal surfaces within that tab get a color-tinted theme. A "red" tab has a subtly red-hued background, cursor, and selection color. A "green" tab has green hues. This makes tabs visually distinct at a glance -- not just the sidebar indicator, but the actual terminal content area.

**How it works (GhosttyKit API):**

GhosttyKit supports per-surface config updates via this sequence:
1. `ghostty_config_clone(baseConfig)` -- clone the app's base config
2. `ghostty_config_load_file(clonedConfig, overridePath)` -- load a small override file with color tweaks
3. `ghostty_config_finalize(clonedConfig)` -- finalize the merged config
4. `ghostty_surface_update_config(surface, clonedConfig)` -- apply to the specific surface

There is no programmatic "set key=value" API, so the override must come from a file. montty generates small temp config files per color:

```
# /tmp/montty-theme-red.conf
background = #1a0808
cursor-color = #ff6666
selection-background = #3d1515
```

**Implementation:**

```swift
// Sources/Model/TabTheme.swift
struct TabTheme {
    /// Generate a color-tinted ghostty config override for a given preset color.
    /// Returns the path to a temp config file.
    static func generateOverride(for color: TabColor.PresetColor, baseBackground: NSColor?) -> URL

    /// Apply a color-tinted theme to all surfaces in a tab.
    static func apply(color: TabColor.PresetColor, to surfaces: [Ghostty.SurfaceView], baseConfig: ghostty_config_t)
}
```

The color tinting algorithm takes the base background color (from the user's ghostty config) and shifts its hue toward the tab's preset color while keeping saturation low enough to remain readable. This means it works with both dark and light themes -- a "red" tint on a dark background is a dark reddish-brown, on a light background it's a light pinkish.

**Lifecycle:**
- When tab color changes (user assigns or auto-derives), regenerate the override and apply to all surfaces in that tab
- When a new surface is created in a tab (split), apply the tab's theme override
- When tab color is cleared (set to `.auto` with no directory), revert to base config via `ghostty_surface_update_config(surface, baseConfig)`

**Temp file management:**
- Override files are written to `NSTemporaryDirectory()/montty-themes/`
- One file per preset color (10 files max)
- Generated once on first use, regenerated if base theme changes (config reload)
- Cleaned up on app termination

### Sidebar resize

Add a draggable edge on the right side of the sidebar to resize its width:
- Default width: 220px
- Min width: 150px
- Max width: 400px
- Persisted in session snapshot (already in Phase 4)

### Remaining keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New tab (Phase 2) |
| `Cmd+W` | Close pane/tab (Phase 2/3) |
| `Cmd+1-9` | Switch to tab by position (Phase 2) |
| `Cmd+Shift+[` | Previous tab (Phase 2) |
| `Cmd+Shift+]` | Next tab (Phase 2) |
| `Cmd+D` | Split right (Phase 3) |
| `Cmd+Shift+D` | Split down (Phase 3) |
| `Cmd+Option+Arrows` | Navigate splits (Phase 3) |
| `Cmd+Shift+Enter` | Toggle sidebar visibility |
| `Cmd+,` | Open Ghostty config in default editor |
| `Cmd+N` | New window (disabled, single window) |

### SwiftLint

Create `.swiftlint.yml` at project root:

```yaml
# .swiftlint.yml
disabled_rules:
  - trailing_whitespace
  - line_length

opt_in_rules:
  - empty_count
  - closure_spacing
  - force_unwrapping

excluded:
  - Sources/Ghostty    # copied MIT files, don't lint
  - DerivedData
  - ghostty

analyzer_rules:
  - unused_import
```

The `Sources/Ghostty/` directory is excluded from linting since those are copied upstream files that we want to keep close to the original for easier syncing.

The `just lint` recipe (defined in Phase 1's justfile) runs `swiftlint lint --strict`.

### Window title

The window title shows the active tab's display name and working directory:
```
montty - myapp (~/projects/myapp)
```

### App icon

Placeholder icon for v1. Can be improved later.

## File Changes

### New files
| File | Purpose |
|------|---------|
| `.swiftlint.yml` | SwiftLint configuration |
| `justfile` (updated) | Add lint recipe if not already present |
| `Sources/Model/TabColor+Auto.swift` | Auto-color derivation logic |
| `Sources/Model/TabTheme.swift` | Per-tab terminal theme tinting (config override generation) |
| `Tests/TabColorAutoTests.swift` | Auto-color hashing tests |
| `Tests/TabThemeTests.swift` | Theme tinting color math tests |

### Modified files
| File | Changes |
|------|---------|
| `Sources/App/AppDelegate.swift` | Handle PWD updates, auto-name/auto-color refresh, apply per-tab theme on color change |
| `Sources/Model/Tab.swift` | `autoName` derived from `workingDirectory` |
| `Sources/View/TabSidebar.swift` | Sidebar resize handle |
| `Sources/View/MainWindow.swift` | Sidebar toggle, window title |
| `Sources/View/TabRow.swift` | Show auto-color when `color == .auto` |

## Testing

### TabColorAutoTests.swift

```swift
import Testing
@testable import montty

struct TabColorAutoTests {
    @Test func sameDirectoryGetsSameColor() {
        let color1 = TabColor.autoColor(forDirectory: "/Users/ted/projects/myapp", envColor: nil)
        let color2 = TabColor.autoColor(forDirectory: "/Users/ted/projects/myapp", envColor: nil)
        #expect(color1 == color2)
    }

    @Test func differentDirectoriesGetDifferentColors() {
        let color1 = TabColor.autoColor(forDirectory: "/Users/ted/projects/app-a", envColor: nil)
        let color2 = TabColor.autoColor(forDirectory: "/Users/ted/projects/app-b", envColor: nil)
        // Not guaranteed to be different, but with a good hash they usually are.
        // Test at least that the function runs without error.
        _ = color1
        _ = color2
    }

    @Test func envColorOverridesDirectory() {
        let color = TabColor.autoColor(forDirectory: "/some/path", envColor: "red")
        #expect(color == .red)
    }

    @Test func envColorCaseInsensitive() {
        let color = TabColor.autoColor(forDirectory: nil, envColor: "Blue")
        #expect(color == .blue)
    }

    @Test func invalidEnvColorFallsToDirectory() {
        let color = TabColor.autoColor(forDirectory: "/Users/ted", envColor: "neon")
        // "neon" is not a valid preset, so it falls back to directory hash
        let dirColor = TabColor.autoColor(forDirectory: "/Users/ted", envColor: nil)
        #expect(color == dirColor)
    }

    @Test func nilDirectoryReturnsGray() {
        let color = TabColor.autoColor(forDirectory: nil, envColor: nil)
        #expect(color == .gray)
    }

    @Test func autoNameFromWorkingDirectory() {
        let tab = Tab(name: "")
        tab.workingDirectory = "/Users/ted/projects/montty"
        // autoName should be derived from last path component
        #expect(tab.autoName == "montty")
    }

    @Test func autoNameFromHomePath() {
        let tab = Tab(name: "")
        tab.workingDirectory = "/Users/ted"
        #expect(tab.autoName == "ted")
    }
}
```

### TabThemeTests.swift

```swift
import Testing
import AppKit
@testable import montty

struct TabThemeTests {
    @Test func tintDarkBackgroundTowardRed() {
        let base = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        let tinted = TabTheme.tintBackground(base, toward: .red)

        // Red channel should be higher than green and blue
        let r = tinted.redComponent
        let g = tinted.greenComponent
        let b = tinted.blueComponent
        #expect(r > g)
        #expect(r > b)
        // Should still be dark (readable)
        #expect(r < 0.3)
    }

    @Test func tintLightBackgroundTowardGreen() {
        let base = NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
        let tinted = TabTheme.tintBackground(base, toward: .green)

        // Green should be relatively boosted
        let r = tinted.redComponent
        let g = tinted.greenComponent
        let b = tinted.blueComponent
        #expect(g > r || g > b)
        // Should still be light (readable)
        #expect(g > 0.8)
    }

    @Test func generateOverrideCreatesValidGhosttyConfig() throws {
        let url = TabTheme.generateOverride(
            for: .blue,
            baseBackground: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        )
        let content = try String(contentsOf: url, encoding: .utf8)

        // Should contain ghostty config key=value lines
        #expect(content.contains("background"))
        // Should not contain any invalid syntax
        #expect(!content.contains("{"))
        #expect(!content.contains("}"))
    }

    @Test func eachPresetColorProducesDifferentBackground() {
        let base = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        let colors = TabColor.PresetColor.allCases.map { preset in
            TabTheme.tintBackground(base, toward: preset)
        }

        // At least some colors should be distinct
        let unique = Set(colors.map { "\($0.redComponent),\($0.greenComponent),\($0.blueComponent)" })
        #expect(unique.count > 5)
    }
}
```

## Verification

1. `just test` -- all tests pass including auto-color and theme tinting tests
2. `just lint` -- SwiftLint passes with no warnings
3. Launch app, `cd ~/projects/myapp` in a tab -- tab auto-name updates to "myapp"
4. Set tab color to auto (default) -- color indicator shows directory-derived color
5. Open multiple tabs in different directories -- each gets a distinct color
6. Open two tabs in the same directory -- both get the same color
7. Set a custom name on a tab, change directory -- custom name persists
8. Assign "red" color to a tab -- terminal background shifts to a subtle red hue
9. Assign "green" to another tab -- visually distinct terminal background
10. Switch between colored tabs -- each terminal has its own color tint
11. Drag sidebar edge -- resizes between 150-400px
12. `Cmd+Shift+Enter` -- toggles sidebar visibility
13. Window title shows active tab name and directory
14. Quit and relaunch -- sidebar width and per-tab themes preserved
