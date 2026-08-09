# montty Control CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `montty` binary that lets a shell, script, or agent restyle the terminal surface and tab it is running in, backed by a single shared write path into the model.

**Architecture:** A new pure `Sources/Control/` module holds the color vocabulary (`TintStop`, `PaneTint`) and the driving port (`ControlCommand`, wire types), compiled by the app, the CLI, and the test target alike. `ControlService.apply` in `Sources/Model/` is the one function that mutates styling state; the CLI, the right-click menu, and the Claude Code hooks all funnel through it. Transport is the existing unix domain socket, relocated to the per-user temp directory and extended with a versioned request/response envelope.

**Tech Stack:** Swift 5, Swift Testing (`import Testing`, `@Test`, `#expect`), xcodegen from `project.yml`, SwiftLint strict, Justfile task runner.

**Spec:** `docs/superpowers/specs/2026-08-08-montty-control-cli-design.md`

## Global Constraints

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- Red/green: write the failing test first, watch it fail, then make it pass. Tests verify observable runtime behavior, never source text.
- Every new file starts with two `// ABOUTME: ` comment lines.
- `Sources/Ghostty/` is upstream code. Do not modify it in this plan.
- `Sources/Control/`, `Sources/Model/`, and `Sources/Persistence/` import Foundation only. No AppKit, no SwiftUI. `montty-unit` compiles them with no test host, so an AppKit import breaks the build.
- Ghostty's C API calls happen on the main actor.
- Run `just check` (test + lint + build) before every commit. Never `--no-verify`.
- Run `just generate` after editing `project.yml` **and after creating any new
  source or test file**. `just test` does not invoke xcodegen, so a brand-new
  file is invisible to every target until it does. Skipping this makes a
  red-state step fail with "no such file" instead of the failure the step is
  actually looking for, which reads as success and is not.
- SwiftLint strict: file length warns at 650 lines, errors at 750; type body warns at 450.
- Full test suite must stay under 5 seconds.
- Protocol version constant is `1`.
- `PaneTint` holds 1 to 3 stops inclusive.
- Never use emojis, emdashes, or hyperbole in documentation.

---

## Task 1: Rename ClaudeCodeStatus to ActivityStatus

Once any process can drive the pane indicator, the Claude-specific names are misnomers. This is a mechanical rename with no behavior change, done first because `ControlCommand` in Task 6 references `ActivityStatus.State`.

**Files:**
- Modify: `Sources/Model/TabInfo.swift` (the `ClaudeCodeStatus` declaration)
- Modify: `Sources/Model/Tab.swift`
- Modify: `Sources/Model/SplitMinimap.swift`
- Modify: `Sources/Model/HookEvent.swift`
- Modify: `Sources/App/HookServer.swift`
- Modify: `Sources/App/DebugServerHandlers.swift`
- Modify: `Sources/View/MinimapView.swift`
- Modify: `docs/debug-server.md`
- Test: `Tests/TabTests.swift`, `Tests/SplitMinimapTests.swift`, `Tests/HookEventTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `ActivityStatus` (was `ClaudeCodeStatus`) with nested `enum State { case working, waiting, idle }`. `Tab.activityStates: [String: ActivityStatus.State]`, `Tab.activityWaitingSince: [String: Date]`, `MinimapPane.activity: ActivityStatus?`, `TabProperties.activityStates`, `SplitMinimap.from(node:focusedLeafID:surfaceTitles:activityStates:surfaceToMonttyID:)`.

Names that stay Claude-specific because only Claude Code reports a cwd: `ClaudeHookEvent`, `ClaudeHookMessage`, `HookDirectoryTracker`, `Tab.claudeDirectories`, `Tab.effectiveSurfaceDirectories`.

- [ ] **Step 1: Update the tests to the new names first**

These are existing passing tests. Renaming them makes them fail to compile, which is the red state for a rename.

In `Tests/TabTests.swift`, `Tests/SplitMinimapTests.swift`, and `Tests/HookEventTests.swift`, apply exactly these substitutions:

| from | to |
|---|---|
| `ClaudeCodeStatus` | `ActivityStatus` |
| `claudeStates` | `activityStates` |
| `claudeWaitingSince` | `activityWaitingSince` |
| `.claudeCode` | `.activity` |

```bash
sed -i '' \
  -e 's/ClaudeCodeStatus/ActivityStatus/g' \
  -e 's/claudeStates/activityStates/g' \
  -e 's/claudeWaitingSince/activityWaitingSince/g' \
  -e 's/\.claudeCode/.activity/g' \
  Tests/TabTests.swift Tests/SplitMinimapTests.swift Tests/HookEventTests.swift
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL to compile, with errors like `cannot find 'ActivityStatus' in scope` and `value of type 'Tab' has no member 'activityStates'`.

- [ ] **Step 3: Apply the rename to the sources**

Apply the same four substitutions across the source files. `Sources/Ghostty/` is excluded.

```bash
sed -i '' \
  -e 's/ClaudeCodeStatus/ActivityStatus/g' \
  -e 's/claudeStates/activityStates/g' \
  -e 's/claudeWaitingSince/activityWaitingSince/g' \
  -e 's/\.claudeCode/.activity/g' \
  Sources/Model/TabInfo.swift Sources/Model/Tab.swift \
  Sources/Model/SplitMinimap.swift Sources/Model/HookEvent.swift \
  Sources/App/HookServer.swift Sources/App/DebugServerHandlers.swift \
  Sources/View/MinimapView.swift
```

Then fix the three things `sed` cannot reach:

1. In `Sources/Model/SplitMinimap.swift`, the `MinimapPane` property is declared as `let claudeCode: ClaudeCodeStatus?`. The `sed` above only rewrites `.claudeCode` with a leading dot, so rename the declaration and its initializer label by hand to `let activity: ActivityStatus?`.

2. In `Sources/App/DebugServerHandlers.swift:135`, the JSON key is a string literal:

```swift
entry["activity"] = [
```

3. In `Sources/View/MinimapView.swift`, rename the view `ClaudeIndicatorView` to `ActivityIndicatorView` and its `state:` parameter stays as is:

```swift
} else if let activity = pane.activity {
    ActivityIndicatorView(state: activity.state)
```

- [ ] **Step 4: Update the debug server doc**

In `docs/debug-server.md`, the `/surfaces` response documents a `claude_code` key. Change the sentence

> The `directory_name`, `git`, and `claude_code` keys appear only when they apply to the surface.

to

> The `directory_name`, `git`, and `activity` keys appear only when they apply to the surface.

- [ ] **Step 5: Run tests and lint to verify they pass**

Run: `just check`
Expected: PASS. No remaining references:

```bash
grep -rn 'ClaudeCodeStatus\|claudeStates\|claudeWaitingSince\|claudeCode' Sources/ Tests/ docs/ | grep -v '^Sources/Ghostty'
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename ClaudeCodeStatus to ActivityStatus

Any process can drive the pane indicator now, so the Claude-specific
name no longer describes what it is. Hook-specific types keep their
names because only Claude Code reports a cwd."
```

---

## Task 2: Add Sources/Control with TintStop

Creates the shared pure module and the stop type. `PaneTint` still holds `[TabColor]` after this task, so nothing else changes and the build stays green.

**Files:**
- Create: `Sources/Control/TintStop.swift`
- Move: `Sources/Model/TabColor.swift` to `Sources/Control/TabColor.swift`
- Modify: `Sources/Model/TabColor+Auto.swift` (move `HueFamily` and `hueFamily` out)
- Modify: `project.yml`
- Test: `Tests/TintStopTests.swift`

**Interfaces:**
- Consumes: `TabColor` (existing 15-case enum).
- Produces: `struct RGB { let r, g, b: UInt8 }` with `init?(hex: String)` and `var text: String`; `enum TintStop { case named(TabColor); case hex(RGB) }` with `static func parse(_:) -> TintStop?`, `var text: String`, `var hueFamily: TabColor.HueFamily`, and `Codable`. `TabColor.HueFamily` and `TabColor.hueFamily` now live in `Sources/Control/TabColor.swift`.

- [ ] **Step 1: Write the failing test**

Create `Tests/TintStopTests.swift`:

```swift
import Foundation
import Testing

@Suite struct TintStopTests {
    @Test func parsesPaletteName() {
        #expect(TintStop.parse("green") == .named(.green))
        #expect(TintStop.parse("brightGreen") == .named(.brightGreen))
    }

    @Test func paletteNameIgnoresCaseAndSeparators() {
        #expect(TintStop.parse("BRIGHTGREEN") == .named(.brightGreen))
        #expect(TintStop.parse("bright-green") == .named(.brightGreen))
        #expect(TintStop.parse("bright_green") == .named(.brightGreen))
    }

    @Test func parsesHexWithAndWithoutHash() {
        let expected = TintStop.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))
        #expect(TintStop.parse("#1a7f37") == expected)
        #expect(TintStop.parse("1a7f37") == expected)
        #expect(TintStop.parse("#1A7F37") == expected)
    }

    @Test func rejectsMalformedInput() {
        #expect(TintStop.parse("#fff") == nil)
        #expect(TintStop.parse("#gggggg") == nil)
        #expect(TintStop.parse("12345g") == nil)
        #expect(TintStop.parse("") == nil)
        #expect(TintStop.parse("chartreuse") == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let stops: [TintStop] = [.named(.brightMagenta), .hex(RGB(r: 0, g: 255, b: 128))]
        for stop in stops {
            let data = try JSONEncoder().encode(stop)
            let decoded = try JSONDecoder().decode(TintStop.self, from: data)
            #expect(decoded == stop)
        }
    }

    @Test func encodesAsPlainString() throws {
        let data = try JSONEncoder().encode(TintStop.named(.green))
        #expect(String(data: data, encoding: .utf8) == "\"green\"")
    }

    @Test func namedStopKeepsItsPaletteHueFamily() {
        #expect(TintStop.named(.brightGreen).hueFamily == .green)
        #expect(TintStop.named(.gray).hueFamily == .neutral)
    }

    @Test func hexStopDerivesHueFamilyFromRGB() {
        #expect(TintStop.parse("#00ff00")?.hueFamily == .green)
        #expect(TintStop.parse("#ff0000")?.hueFamily == .red)
        #expect(TintStop.parse("#0000ff")?.hueFamily == .blue)
        #expect(TintStop.parse("#00ffff")?.hueFamily == .cyan)
        #expect(TintStop.parse("#ff00ff")?.hueFamily == .magenta)
        #expect(TintStop.parse("#ffff00")?.hueFamily == .yellow)
    }

    @Test func desaturatedHexIsNeutral() {
        #expect(TintStop.parse("#808080")?.hueFamily == .neutral)
        #expect(TintStop.parse("#ffffff")?.hueFamily == .neutral)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL to compile with `cannot find 'TintStop' in scope`.

- [ ] **Step 3: Move TabColor and its hue families into Sources/Control**

```bash
mkdir -p Sources/Control
git mv Sources/Model/TabColor.swift Sources/Control/TabColor.swift
```

`Sources/Control/TabColor.swift` becomes (the enum is unchanged; the `HueFamily` block moves here from `TabColor+Auto.swift`):

```swift
// ABOUTME: Terminal tab colors mapped to ANSI-16 palette slots, plus the hue
// ABOUTME: families that keep two stops in one gradient tellable apart.

import Foundation

/// Terminal tab colors mapped to ANSI-16 palette slots.
/// Gray is reserved for directories not in a git repo.
enum TabColor: String, Codable, CaseIterable {
    case red, green, yellow, blue, magenta, cyan
    case brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan
    /// Used for dark themes (ANSI 7) or light themes (ANSI 0).
    case neutral
    /// Used for dark themes (ANSI 15) or light themes (ANSI 8).
    case neutralBright
    case gray
}

extension TabColor {
    /// Hue families collapse each base/bright pair, which read as one color at a
    /// glance. Knockout removes a whole family so a gradient never sets green
    /// beside brightGreen.
    enum HueFamily: Hashable {
        case red, green, yellow, blue, magenta, cyan, neutral
    }

    var hueFamily: HueFamily {
        switch self {
        case .red, .brightRed: .red
        case .green, .brightGreen: .green
        case .yellow, .brightYellow: .yellow
        case .blue, .brightBlue: .blue
        case .magenta, .brightMagenta: .magenta
        case .cyan, .brightCyan: .cyan
        case .neutral, .neutralBright, .gray: .neutral
        }
    }
}
```

Delete the `HueFamily` enum and the `var hueFamily` property from `Sources/Model/TabColor+Auto.swift`. Everything else in that file stays.

- [ ] **Step 4: Write TintStop**

Create `Sources/Control/TintStop.swift`:

```swift
// ABOUTME: One gradient stop: a themed ANSI palette slot, or a literal RGB
// ABOUTME: color set from the montty CLI.

import Foundation

/// A literal 24-bit color.
struct RGB: Equatable, Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
}

extension RGB {
    /// Six hex digits without a leading `#`. Rejects any other length and any
    /// non-hex character, so partial scans never slip through.
    init?(hex: String) {
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        self.init(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    var text: String { String(format: "#%02x%02x%02x", Int(r), Int(g), Int(b)) }

    /// The hue family this color reads as, so a CLI-set stop still knocks out
    /// its own family when montty builds a repo gradient around it.
    var hueFamily: TabColor.HueFamily {
        let red = Double(r) / 255, green = Double(g) / 255, blue = Double(b) / 255
        let highest = max(red, green, blue)
        let lowest = min(red, green, blue)
        let delta = highest - lowest
        guard delta > 0.08 else { return .neutral }

        var hue: Double
        if highest == red {
            hue = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if highest == green {
            hue = 60 * ((blue - red) / delta + 2)
        } else {
            hue = 60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }

        switch hue {
        case ..<30, 330...: return .red
        case ..<90: return .yellow
        case ..<150: return .green
        case ..<210: return .cyan
        case ..<270: return .blue
        default: return .magenta
        }
    }
}

/// One stop in a pane's gradient.
enum TintStop: Equatable, Hashable {
    case named(TabColor)
    case hex(RGB)
}

extension TintStop {
    /// Parse one stop. A leading `#` forces hex; otherwise a palette name wins
    /// and a bare six-digit hex value is the fallback, because bash treats an
    /// unquoted `#` as a comment introducer.
    static func parse(_ text: String) -> TintStop? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            return RGB(hex: String(trimmed.dropFirst())).map(TintStop.hex)
        }

        let normalized = trimmed.lowercased().filter { $0 != "-" && $0 != "_" }
        if let color = TabColor.allCases.first(
            where: { $0.rawValue.lowercased() == normalized }
        ) {
            return .named(color)
        }
        return RGB(hex: trimmed).map(TintStop.hex)
    }

    var text: String {
        switch self {
        case .named(let color): color.rawValue
        case .hex(let rgb): rgb.text
        }
    }

    var hueFamily: TabColor.HueFamily {
        switch self {
        case .named(let color): color.hueFamily
        case .hex(let rgb): rgb.hueFamily
        }
    }
}

extension TintStop: Codable {
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let stop = TintStop.parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "unrecognized tint stop \"\(text)\""
            )
        }
        self = stop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
```

- [ ] **Step 5: Add Sources/Control to the targets**

In `project.yml`, the app target's `sources` is `- path: Sources`, which already picks up the new directory. Add it to the test target so the pure types compile without a test host. Change the `montty-unit` sources block (`project.yml:124`) to:

```yaml
    sources:
      - path: Tests
      - path: Sources/Control
      - path: Sources/Model
      - path: Sources/Persistence
```

- [ ] **Step 6: Regenerate, then run tests to verify they pass**

Run: `just generate && just check`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add TintStop for named and literal pane colors

TabColor stays a closed enum meaning an ANSI palette slot. TintStop is
what actually renders, so hex can only ever enter through an override and
never reaches the repo hash palette."
```

---

## Task 3: Move PaneTint into Control and hold TintStop

`PaneTint` currently lives at the bottom of `Sources/Model/TabColor+Auto.swift` and holds `[TabColor]`. It becomes the shared currency for all three override scopes, so it moves to `Sources/Control/` and holds `[TintStop]`. The SwiftUI rendering path is updated in the same task to keep the build green.

**Files:**
- Create: `Sources/Control/PaneTint.swift`
- Modify: `Sources/Model/TabColor+Auto.swift` (delete the `PaneTint` struct, update construction sites)
- Modify: `Sources/View/TabRow.swift` (move `swiftUIColor` from `TabColor` to `TintStop`)
- Test: `Tests/PaneTintTests.swift`

**Interfaces:**
- Consumes: `TintStop`, `TabColor` from Task 2.
- Produces: `struct PaneTint { let stops: [TintStop] }` with `init(stops:)` clamping to `maxStops = 3` and substituting `[.named(.gray)]` when empty, `var primary: TintStop`, `var leading: TintStop`, `var isGradient: Bool`, and `Codable` that decodes a bare string or an array and encodes a single stop as a bare string. `TintStop.swiftUIColor` replaces `TabColor.swiftUIColor`.
- `TabColor.knockout(for:avoiding:mixed:)` now takes `avoiding taken: [TintStop]` and still returns `TabColor?`.

- [ ] **Step 1: Write the failing test**

Create `Tests/PaneTintTests.swift`:

```swift
import Foundation
import Testing

@Suite struct PaneTintTests {
    @Test func emptyStopsFallBackToGray() {
        #expect(PaneTint(stops: []).stops == [.named(.gray)])
    }

    @Test func clampsToThreeStops() {
        let tint = PaneTint(stops: [
            .named(.red), .named(.green), .named(.blue), .named(.cyan)
        ])
        #expect(tint.stops.count == 3)
        #expect(tint.stops == [.named(.red), .named(.green), .named(.blue)])
    }

    @Test func primaryIsTrailingStopAndLeadingIsFirst() {
        let tint = PaneTint(stops: [.named(.red), .named(.green)])
        #expect(tint.primary == .named(.green))
        #expect(tint.leading == .named(.red))
        #expect(tint.isGradient)
        #expect(!PaneTint(stops: [.named(.red)]).isGradient)
    }

    @Test func decodesBareStringFromV2Sessions() throws {
        let data = Data("\"green\"".utf8)
        let tint = try JSONDecoder().decode(PaneTint.self, from: data)
        #expect(tint.stops == [.named(.green)])
    }

    @Test func decodesArrayOfStops() throws {
        let data = Data("[\"neutralBright\",\"#1a7f37\"]".utf8)
        let tint = try JSONDecoder().decode(PaneTint.self, from: data)
        #expect(tint.stops == [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
    }

    @Test func encodesSingleStopAsBareStringForOlderBuilds() throws {
        let data = try JSONEncoder().encode(PaneTint(stops: [.named(.green)]))
        #expect(String(data: data, encoding: .utf8) == "\"green\"")
    }

    @Test func encodesGradientAsArray() throws {
        let tint = PaneTint(stops: [.named(.neutralBright), .named(.green)])
        let data = try JSONEncoder().encode(tint)
        #expect(String(data: data, encoding: .utf8) == "[\"neutralBright\",\"green\"]")
    }

    @Test func roundTripsBothShapes() throws {
        let cases = [
            PaneTint(stops: [.named(.blue)]),
            PaneTint(stops: [.named(.blue), .hex(RGB(r: 1, g: 2, b: 3))]),
            PaneTint(stops: [.named(.blue), .named(.red), .named(.cyan)])
        ]
        for tint in cases {
            let data = try JSONEncoder().encode(tint)
            #expect(try JSONDecoder().decode(PaneTint.self, from: data) == tint)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL. `PaneTint` exists but holds `[TabColor]`, so `PaneTint(stops: [.named(.gray)])` does not compile and the Codable tests have no conformance to call.

- [ ] **Step 3: Create Sources/Control/PaneTint.swift**

```swift
// ABOUTME: Ordered gradient stops for a pane, leading edge to trailing edge.
// ABOUTME: The shared currency for surface, tab, and repo color overrides.

import Foundation

/// One stop renders solid, two is a repo's own signature, and three is a
/// worktree carrying its parent repo's pair ahead of its own color.
struct PaneTint: Equatable, Hashable {
    static let maxStops = 3

    let stops: [TintStop]

    init(stops: [TintStop]) {
        let clamped = Array(stops.prefix(Self.maxStops))
        self.stops = clamped.isEmpty ? [.named(.gray)] : clamped
    }

    /// The stop to use wherever only one can be shown. Always the trailing
    /// stop: a repo's own color, or a worktree's own color.
    var primary: TintStop { stops.last ?? .named(.gray) }

    /// The leading stop, used for the tab row's left edge bar.
    var leading: TintStop { stops.first ?? .named(.gray) }

    var isGradient: Bool { stops.count > 1 }
}

extension PaneTint: Codable {
    /// Accepts a bare string from a v2 session or an array of stops. One
    /// decoder covers every migration point, so no field needs a version
    /// branch of its own.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(TintStop.self) {
            self.init(stops: [single])
            return
        }
        self.init(stops: try container.decode([TintStop].self))
    }

    /// A single stop encodes back as a bare string, so a session without
    /// gradients stays readable by a build that predates this format.
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if stops.count == 1 {
            try container.encode(stops[0])
        } else {
            try container.encode(stops)
        }
    }
}
```

- [ ] **Step 4: Delete the old PaneTint and update its construction sites**

Delete the entire `struct PaneTint` declaration from the bottom of `Sources/Model/TabColor+Auto.swift`.

In the same file, change `knockout` to take stops rather than colors:

```swift
    /// Pick a stop for `identity`, skipping every color whose hue family is
    /// already spoken for. Returns nil only if the palette is exhausted.
    static func knockout(
        for identity: String,
        avoiding taken: [TintStop],
        mixed: Bool = true
    ) -> TabColor? {
        let usedFamilies = Set(taken.map(\.hueFamily))
        let colors = TabColor.allCases.filter {
            $0 != .gray && !usedFamilies.contains($0.hueFamily)
        }
        guard !colors.isEmpty else { return nil }
        let hash = mixed ? mixedHash(identity) : polynomialHash(identity)
        return colors[Int(hash % UInt64(colors.count))]
    }
```

Then update every `PaneTint(stops:)` call in `paneTint(for:overrides:)` and `resolvedPaneTint(...)` to wrap palette colors in `.named(...)`. The full replacement for those two functions:

```swift
    /// Gradient stops for a git location. A repo gets its own two-color
    /// signature. A worktree carries its parent repo's signature on the leading
    /// edge and its own color on the trailing edge, so every worktree of a repo
    /// starts with the same pattern. An explicitly picked color renders solid.
    static func paneTint(for info: GitInfo, overrides: [String: TabColor] = [:]) -> PaneTint? {
        let identity = info.repoPath + (info.worktreeName ?? "")
        if let picked = overrides[identity] {
            return PaneTint(stops: [.named(picked)])
        }
        guard let own = colorForGitInfo(info, overrides: overrides) else { return nil }

        let parentInfo = GitInfo(
            repoName: info.repoName,
            branchName: nil,
            worktreeName: nil,
            repoPath: info.repoPath
        )
        let parentStops: [TintStop]
        if let picked = overrides[parentInfo.repoPath] {
            parentStops = [.named(picked)]
        } else if let parentPrimary = colorForGitInfo(parentInfo, overrides: overrides) {
            let leading = knockout(for: parentInfo.repoPath, avoiding: [.named(parentPrimary)])
            parentStops = [.named(leading ?? parentPrimary), .named(parentPrimary)]
        } else {
            parentStops = [.named(own)]
        }

        guard info.worktreeName != nil else { return PaneTint(stops: parentStops) }
        // The worktree's own stop knocks out both parent families, so all three
        // bands stay tellable apart.
        let ownStop = knockout(for: identity, avoiding: parentStops, mixed: false)
        return PaneTint(stops: parentStops + [.named(ownStop ?? own)])
    }

    /// Resolve the pane tint for a directory.
    /// Priority: tab override (always solid) > git signature > nil.
    static func resolvedPaneTint(
        tabColorOverride: TabColor?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: TabColor]
    ) -> PaneTint? {
        if let tabColorOverride {
            return PaneTint(stops: [.named(tabColorOverride)])
        }
        guard let dir = surfaceDirectory, let info = GitInfo.from(path: dir) else {
            return nil
        }
        return paneTint(for: info, overrides: repoColorOverrides)
    }
```

The override dictionaries stay `[String: TabColor]` for now. Task 4 widens them.

In `Sources/Model/Tab.swift`, `effectiveColor(overrides:)` returns `effectivePaneTint(overrides:).primary`, whose type is now `TintStop`. Change its signature:

```swift
    /// The effective color for this tab. Priority: tab override > repo override > git hash > gray.
    func effectiveColor(overrides: [String: TabColor] = [:]) -> TintStop {
        effectivePaneTint(overrides: overrides).primary
    }
```

and the gray fallback in `effectivePaneTint`:

```swift
        ) ?? PaneTint(stops: [.named(.gray)])
```

- [ ] **Step 5: Move swiftUIColor from TabColor to TintStop**

In `Sources/View/TabRow.swift`, the `extension TabColor` at line 144 owns `orderedCases`, `swiftUIColor`, `catppuccinFallback`, and `catppuccinHex`. Keep `orderedCases` and the Catppuccin table on `TabColor`, and move the public entry point to `TintStop`. Replace the `swiftUIColor` and `catppuccinFallback` properties with:

```swift
extension TabColor {
    /// Color from the user's Ghostty theme palette, with Catppuccin fallback.
    var swiftUIColor: Color {
        if self == .gray { return .gray }
        if let idx = Self.orderedCases.firstIndex(of: self),
           let appDel = AppDelegate.shared(),
           idx < appDel.tabPalette.count {
            return Color(nsColor: appDel.tabPalette[idx])
        }
        return catppuccinFallback
    }

    /// Catppuccin Mocha fallback for when the Ghostty palette isn't available
    /// (tests, or before config loads).
    private var catppuccinFallback: Color {
        let hex = catppuccinHex
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension TintStop {
    /// A named stop resolves through the Ghostty theme palette. A hex stop is
    /// already literal and renders as given.
    var swiftUIColor: Color {
        switch self {
        case .named(let color): color.swiftUIColor
        case .hex(let rgb):
            Color(
                red: Double(rgb.r) / 255,
                green: Double(rgb.g) / 255,
                blue: Double(rgb.b) / 255
            )
        }
    }
}
```

`Sources/View/PaneTint+SwiftUI.swift` needs no change: `stops.map { $0.swiftUIColor }` now resolves through `TintStop`.

In `Sources/View/TabRow.swift`, `Sources/View/TabSidebar.swift`, and `Sources/View/TabContextMenu.swift`, any call to `tab.effectiveColor(overrides:)` now yields a `TintStop`. Where the result is passed to something expecting a `Color`, `.swiftUIColor` still works. Where `TabColorPicker(currentColor:)` receives it, pass `tab.effectiveColor(overrides: repoColorOverrides)` unchanged and widen the picker's parameter:

```swift
struct TabColorPicker: View {
    let currentColor: TintStop
```

and its comparison:

```swift
                Image(nsImage: colorSwatch(
                    color.swiftUIColor,
                    checked: .named(color) == currentColor
                ))
```

In `Sources/View/TabContextMenu.swift`, the repo swatch currently comes from `TabColor.colorForWorktree(...) ?? .gray`, a `TabColor`. Wrap it:

```swift
            let repoColor = TintStop.named(
                TabColor.colorForWorktree(focusedDir, overrides: repoColorOverrides) ?? .gray
            )
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `just check`
Expected: PASS. Existing `Tests/TabColorAutoTests.swift` assertions that compare `tint.stops` to `[TabColor]` values will need `.named(...)` wrapping; update them mechanically as compile errors point at them.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: PaneTint holds TintStop and moves to Control

Gradient stops become the shared currency for every override scope, and
rendering resolves through TintStop so hex and palette colors take the
same path."
```

---

## Task 4: Widen the three override scopes to PaneTint

Adds per-surface overrides and lets tab and repo overrides be gradients. Precedence becomes surface > tab > repo > git > gray.

**Files:**
- Modify: `Sources/Model/TabColor+Auto.swift` (`paneTint`, `resolvedPaneTint`, `colorForGitInfo`)
- Modify: `Sources/Model/Tab.swift`
- Modify: `Sources/App/AppDelegate.swift:28` (`repoColorOverrides` type)
- Modify: `Sources/View/MinimapView.swift`, `Sources/View/SplitContainerView.swift`, `Sources/View/TabSidebar.swift`, `Sources/View/TabContextMenu.swift`, `Sources/View/TabColorPicker.swift`, `Sources/App/MainWindow.swift` (signature updates only)
- Test: `Tests/PaneTintPrecedenceTests.swift`

**Interfaces:**
- Consumes: `PaneTint` from Task 3.
- Produces: `Tab.surfaceColorOverrides: [UUID: PaneTint]` keyed by surfaceID; `Tab.colorOverride: PaneTint?`; `AppDelegate.repoColorOverrides: [String: PaneTint]`; `TabColor.resolvedPaneTint(surfaceOverride:tabColorOverride:surfaceDirectory:repoColorOverrides:) -> PaneTint?`; `TabColor.paneTint(for:overrides:)` taking `[String: PaneTint]`.
- `TabColor.colorForGitInfo(_:)` and `TabColor.colorForWorktree(_:)` lose their `overrides:` parameter. Override lookup is `paneTint`'s job now, and it is the only display path.

- [ ] **Step 1: Write the failing test**

Create `Tests/PaneTintPrecedenceTests.swift`:

```swift
import Foundation
import Testing

@Suite struct PaneTintPrecedenceTests {
    private let surfaceTint = PaneTint(stops: [.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
    private let tabTint = PaneTint(stops: [.named(.blue), .named(.red)])

    @Test func surfaceOverrideBeatsEverything() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: surfaceTint,
            tabColorOverride: tabTint,
            surfaceDirectory: "/tmp",
            repoColorOverrides: [:]
        )
        #expect(tint == surfaceTint)
    }

    @Test func tabOverrideBeatsRepoAndGit() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: tabTint,
            surfaceDirectory: "/tmp",
            repoColorOverrides: ["/tmp": PaneTint(stops: [.named(.cyan)])]
        )
        #expect(tint == tabTint)
    }

    @Test func tabOverrideKeepsItsGradient() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: tabTint,
            surfaceDirectory: nil,
            repoColorOverrides: [:]
        )
        #expect(tint?.stops.count == 2)
        #expect(tint?.isGradient == true)
    }

    @Test func repoOverrideWinsOverGitSignature() {
        let info = GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
        let picked = PaneTint(stops: [.named(.cyan), .hex(RGB(r: 9, g: 9, b: 9))])
        let tint = TabColor.paneTint(
            for: info, overrides: ["/Users/ted/montty": picked]
        )
        #expect(tint == picked)
    }

    @Test func noOverrideAndNoRepoIsNil() {
        let tint = TabColor.resolvedPaneTint(
            surfaceOverride: nil,
            tabColorOverride: nil,
            surfaceDirectory: "/tmp",
            repoColorOverrides: [:]
        )
        #expect(tint == nil)
    }

    @Test func tabExposesPerSurfaceOverride() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.surfaceColorOverrides[surfaceID] = surfaceTint
        #expect(tab.effectivePaneTint() == surfaceTint)
    }

    @Test func surfaceOverrideOnFocusedPaneShowsInSidebar() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        tab.colorOverride = tabTint
        tab.surfaceColorOverrides[surfaceID] = surfaceTint
        #expect(tab.effectiveColor() == surfaceTint.primary)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL to compile: `resolvedPaneTint` has no `surfaceOverride:` parameter and `Tab` has no `surfaceColorOverrides`.

- [ ] **Step 3: Widen the resolution functions**

In `Sources/Model/TabColor+Auto.swift`, drop the `overrides:` parameter from the two hash helpers, because `paneTint` owns override lookup:

```swift
    /// Derive a color from git repo identity.
    /// Same repo+worktree always produces the same color.
    /// Returns nil if not in a git repo (no tinting).
    static func colorForGitInfo(_ gitInfo: GitInfo?) -> TabColor? {
        guard let gitInfo else { return nil }
        let identity = gitInfo.repoPath + (gitInfo.worktreeName ?? "")
        // Gray is reserved for "no git repo" -- exclude it from the hash palette
        let colors = TabColor.allCases.filter { $0 != .gray }
        return colors[Int(polynomialHash(identity) % UInt64(colors.count))]
    }

    /// Derive a color from a directory path via its git repo.
    /// Returns nil if not in a git repo.
    static func colorForWorktree(_ dir: String?) -> TabColor? {
        guard let dir else { return nil }
        return colorForGitInfo(GitInfo.from(path: dir))
    }
```

Delete `resolvedPaneColor(...)` entirely; nothing calls it once the views move to tints.

Rewrite `paneTint` and `resolvedPaneTint` to take `[String: PaneTint]`:

```swift
    static func paneTint(for info: GitInfo, overrides: [String: PaneTint] = [:]) -> PaneTint? {
        let identity = info.repoPath + (info.worktreeName ?? "")
        if let picked = overrides[identity] { return picked }
        guard let own = colorForGitInfo(info) else { return nil }

        let parentInfo = GitInfo(
            repoName: info.repoName,
            branchName: nil,
            worktreeName: nil,
            repoPath: info.repoPath
        )
        let parentStops: [TintStop]
        if let picked = overrides[parentInfo.repoPath] {
            parentStops = picked.stops
        } else if let parentPrimary = colorForGitInfo(parentInfo) {
            let leading = knockout(for: parentInfo.repoPath, avoiding: [.named(parentPrimary)])
            parentStops = [.named(leading ?? parentPrimary), .named(parentPrimary)]
        } else {
            parentStops = [.named(own)]
        }

        guard info.worktreeName != nil else { return PaneTint(stops: parentStops) }
        let ownStop = knockout(for: identity, avoiding: parentStops, mixed: false)
        return PaneTint(stops: parentStops + [.named(ownStop ?? own)])
    }

    /// Resolve the pane tint for a surface.
    /// Priority: surface override > tab override > repo override > git signature > nil.
    static func resolvedPaneTint(
        surfaceOverride: PaneTint?,
        tabColorOverride: PaneTint?,
        surfaceDirectory: String?,
        repoColorOverrides: [String: PaneTint]
    ) -> PaneTint? {
        if let surfaceOverride { return surfaceOverride }
        if let tabColorOverride { return tabColorOverride }
        guard let dir = surfaceDirectory, let info = GitInfo.from(path: dir) else {
            return nil
        }
        return paneTint(for: info, overrides: repoColorOverrides)
    }

    /// The repo identity string for a directory, used as the key in overrides.
    /// Returns nil if not in a git repo.
    static func repoIdentity(for dir: String?) -> String? {
        guard let dir, let gitInfo = GitInfo.from(path: dir) else { return nil }
        return gitInfo.repoPath + (gitInfo.worktreeName ?? "")
    }
```

- [ ] **Step 4: Add per-surface overrides to Tab**

In `Sources/Model/Tab.swift`, change the override property and add the new dictionary:

```swift
    /// Per-surface color override, keyed by surfaceID. Beats the tab override.
    var surfaceColorOverrides: [UUID: PaneTint] = [:]
    /// Tab-level color override. Beats repo/worktree colors for all surfaces in this tab.
    var colorOverride: PaneTint?
```

and route both resolution helpers through the new precedence:

```swift
    /// The effective color for this tab. Priority: surface > tab > repo > git hash > gray.
    func effectiveColor(overrides: [String: PaneTint] = [:]) -> TintStop {
        effectivePaneTint(overrides: overrides).primary
    }

    /// The effective tint for this tab, including the worktree-gradient secondary
    /// stop when the focused pane is in a linked worktree. Falls back to a solid
    /// gray tint when there's no git info.
    func effectivePaneTint(overrides: [String: PaneTint] = [:]) -> PaneTint {
        let dirs = effectiveSurfaceDirectories
        let surfaceID = focusedSurfaceID
        let dir = surfaceID.flatMap { dirs[$0] }
        return TabColor.resolvedPaneTint(
            surfaceOverride: surfaceID.flatMap { surfaceColorOverrides[$0] },
            tabColorOverride: colorOverride,
            surfaceDirectory: dir,
            repoColorOverrides: overrides
        ) ?? PaneTint(stops: [.named(.gray)])
    }
```

- [ ] **Step 5: Update the call sites**

In `Sources/App/AppDelegate.swift:28`:

```swift
    @Published var repoColorOverrides: [String: PaneTint] = [:]
```

Change every `[String: TabColor]` property and parameter to `[String: PaneTint]`, and every `tabColorOverride: TabColor?` to `PaneTint?`, in:

- `Sources/View/SplitContainerView.swift:9,10,116,117,129,130`
- `Sources/View/MinimapView.swift:6,10`
- `Sources/View/TabSidebar.swift:7,8,9`
- `Sources/View/TabRow.swift:6`
- `Sources/View/TabContextMenu.swift:5,7,8`
- `Sources/App/MainWindow.swift:24`

Both `SplitContainerView.swift:72` and `MinimapView.swift:57` call `TabColor.resolvedPaneTint`. Give each the new first argument. In `MinimapView`, the per-pane surface override comes from the pane being drawn:

```swift
        TabColor.resolvedPaneTint(
            surfaceOverride: surfaceColorOverrides[pane.surfaceID],
            tabColorOverride: tabColorOverride,
            surfaceDirectory: surfaceDirectories[pane.surfaceID],
            repoColorOverrides: repoColorOverrides
        )
```

Add a `var surfaceColorOverrides: [UUID: PaneTint] = [:]` property to `MinimapView` and `SplitContainerView`, and pass `tab.surfaceColorOverrides` from `TabRow` and `MainWindow` respectively.

In `Sources/View/TabColorPicker.swift`, the picker still offers single named colors. Its `onSelect` now produces a `PaneTint?`:

```swift
struct TabColorPicker: View {
    let currentColor: TintStop
    let hasOverride: Bool
    /// Called with a tint to set an override, or nil to clear the override.
    let onSelect: (PaneTint?) -> Void

    var body: some View {
        ForEach(TabColor.allCases.filter { $0 != .gray }, id: \.self) { color in
            Button {
                onSelect(PaneTint(stops: [.named(color)]))
            } label: {
                Image(nsImage: colorSwatch(
                    color.swiftUIColor,
                    checked: .named(color) == currentColor
                ))
            }
        }

        if hasOverride {
            Divider()

            Button {
                onSelect(nil)
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
    }
}
```

In `Sources/View/TabContextMenu.swift`, the repo swatch loses the `overrides:` argument that `colorForWorktree` no longer takes, and reads the override tint directly:

```swift
            let repoColor = repoColorOverrides[identity]?.primary
                ?? TintStop.named(TabColor.colorForWorktree(focusedDir) ?? .gray)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `just check`
Expected: PASS. `Tests/TabColorAutoTests.swift` calls `colorForGitInfo(info, overrides:)` and `colorForWorktree(dir, overrides:)`; drop the `overrides:` argument from those calls, and move any override-behavior assertions to use `TabColor.paneTint(for:overrides:)` with `PaneTint` values.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: per-surface color overrides with surface > tab > repo precedence

All three override scopes carry a PaneTint, so any of them can be a
gradient, and a pane keeps its own color when the tab is also colored."
```

---

## Task 5: Session format v3 and store hardening

`version` exists in the snapshot but is never branched on. This makes it load-bearing and stops two silent data-loss paths.

**Files:**
- Modify: `Sources/Persistence/SessionSnapshot.swift`
- Modify: `Sources/Persistence/SessionStore.swift`
- Modify: `Sources/App/AppDelegate.swift` (`createSnapshot`, `restoreSession`)
- Test: `Tests/SessionSnapshotTests.swift`, `Tests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `PaneTint` from Task 3.
- Produces: `SessionSnapshot.currentVersion == 3`; `SessionSnapshot.colorOverride` and `repoColorOverrides` typed `PaneTint`; `TabSnapshot.leafColorOverrides: [UUID: PaneTint]`; `SessionStore.load() -> SessionSnapshot?` quarantining unparseable files; `SessionStore.LoadFailure` enum with `.corrupt` and `.tooNew`.

Leaf ID is the persistence key because `restoreSplitNode` (`Sources/App/AppDelegate.swift:588`) mints fresh surfaceIDs on restore but preserves leaf IDs, the same reason `leafDirectories` works.

- [ ] **Step 1: Write the failing test**

Create `Tests/SessionStoreTests.swift`:

```swift
import Foundation
import Testing

@Suite struct SessionStoreTests {
    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("montty-store-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadsAV2SessionWithBareStringColors() throws {
        let dir = tempDir()
        let json = """
        {"version":2,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[],"repoColorOverrides":{"/repo":"green"}}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        let snapshot = SessionStore(directory: dir).load()
        #expect(snapshot?.repoColorOverrides["/repo"] == PaneTint(stops: [.named(.green)]))
    }

    @Test func refusesASessionFromANewerVersion() throws {
        let dir = tempDir()
        let json = """
        {"version":99,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        #expect(SessionStore(directory: dir).load() == nil)
    }

    @Test func quarantinesAnUnparseableFileInsteadOfOverwritingIt() throws {
        let dir = tempDir()
        let path = dir.appendingPathComponent("session.json")
        try Data("{ not json".utf8).write(to: path)

        let store = SessionStore(directory: dir)
        #expect(store.load() == nil)
        store.save(snapshot: SessionSnapshot(tabs: []))

        let names = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("session.corrupt-") }
        #expect(names.count == 1)

        let quarantined = try String(
            contentsOf: dir.appendingPathComponent(names[0]), encoding: .utf8
        )
        #expect(quarantined == "{ not json")
    }

    @Test func backsUpThePreviousFileWhenTheVersionChanges() throws {
        let dir = tempDir()
        let json = """
        {"version":2,"windowX":0,"windowY":0,"windowWidth":100,"windowHeight":100,
         "activeTabID":null,"tabs":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("session.json"))

        let store = SessionStore(directory: dir)
        _ = store.load()
        store.save(snapshot: SessionSnapshot(tabs: []))

        let backup = dir.appendingPathComponent("session.v2.json")
        #expect(FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func roundTripsGradientOverrides() throws {
        let dir = tempDir()
        let store = SessionStore(directory: dir)
        let tint = PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        store.save(snapshot: SessionSnapshot(
            tabs: [], repoColorOverrides: ["/repo": tint]
        ))
        #expect(store.load()?.repoColorOverrides["/repo"] == tint)
    }
}
```

Append to `Tests/SessionSnapshotTests.swift`:

```swift
    @Test func leafColorOverridesRoundTrip() throws {
        let leafID = UUID()
        let tint = PaneTint(stops: [.named(.blue), .named(.red)])
        let snapshot = SessionSnapshot(tabs: [
            TabSnapshot(
                tabID: UUID(), name: "review", position: 0,
                focusedLeafID: leafID,
                splitLayout: .leaf(SurfaceLeaf(id: leafID, surfaceID: UUID())),
                leafDirectories: [:],
                leafColorOverrides: [leafID: tint],
                colorOverride: nil
            )
        ])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: data)
        #expect(decoded.tabs[0].leafColorOverrides[leafID] == tint)
        #expect(decoded.version == 3)
    }
```

The two existing assertions `#expect(decoded.version == 2)` at `Tests/SessionSnapshotTests.swift:27` and `:121` become `== 3`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `just test`
Expected: FAIL. `TabSnapshot` has no `leafColorOverrides`, `SessionStore` has no quarantine behavior, and the version assertions read 2.

- [ ] **Step 3: Bump the snapshot to v3**

In `Sources/Persistence/SessionSnapshot.swift`:

```swift
    static let currentVersion = 3
```

Change the two override properties and both initializers to `PaneTint`:

```swift
    var repoColorOverrides: [String: PaneTint] = [:]
```

```swift
        repoColorOverrides: [String: PaneTint] = [:]
```

```swift
        repoColorOverrides = try container.decodeIfPresent(
            [String: PaneTint].self, forKey: .repoColorOverrides
        ) ?? [:]
```

And in `TabSnapshot`:

```swift
struct TabSnapshot: Codable {
    var tabID: UUID
    var name: String
    var position: Int
    var focusedLeafID: UUID?
    var splitLayout: SplitNode
    /// Working directory per leaf, keyed by leaf ID.
    var leafDirectories: [UUID: String]
    /// Per-surface color override, keyed by leaf ID. Surfaces get fresh IDs on
    /// restore; leaf IDs survive, which is what makes this stick.
    var leafColorOverrides: [UUID: PaneTint] = [:]
    /// Tab-level color override, if set.
    var colorOverride: PaneTint?
}
```

`PaneTint`'s lenient decoder handles the v2 bare-string form for both `repoColorOverrides` and `colorOverride`, so neither needs a version branch. `leafColorOverrides` defaults to empty when absent.

- [ ] **Step 4: Harden the store**

Replace `load()` and `save(snapshot:)` in `Sources/Persistence/SessionStore.swift`:

```swift
    /// Tracks what the last load saw, so the first save can protect whatever is
    /// already on disk before overwriting it.
    private enum PriorFile {
        case none
        case readable(version: Int)
        case unreadable
    }

    private var priorFile: PriorFile = .none
    private var didProtectPriorFile = false

    func save(snapshot: SessionSnapshot) {
        protectPriorFileIfNeeded()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to save session: \(error)")
        }
    }

    func load() -> SessionSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            priorFile = .none
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: data)
            priorFile = .readable(version: snapshot.version)
            guard snapshot.version <= SessionSnapshot.currentVersion else {
                Self.logger.error("""
                    Session version \(snapshot.version) is newer than \
                    \(SessionSnapshot.currentVersion); refusing to load
                    """)
                return nil
            }
            return snapshot
        } catch {
            Self.logger.error("Failed to load session: \(error)")
            priorFile = .unreadable
            return nil
        }
    }

    /// Runs once before the first save. An unreadable file is moved aside so the
    /// autosave timer cannot destroy the evidence, and a file written by a
    /// different version is copied aside so a rollback has something to read.
    private func protectPriorFileIfNeeded() {
        guard !didProtectPriorFile else { return }
        didProtectPriorFile = true

        let directory = fileURL.deletingLastPathComponent()
        switch priorFile {
        case .none:
            return
        case .unreadable:
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = directory
                .appendingPathComponent("session.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: quarantine)
            Self.logger.error("Quarantined unreadable session at \(quarantine.path)")
        case .readable(let version):
            guard version != SessionSnapshot.currentVersion else { return }
            let backup = directory.appendingPathComponent("session.v\(version).json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            Self.logger.info("Backed up v\(version) session to \(backup.path)")
        }
    }
```

- [ ] **Step 5: Persist and restore the per-surface overrides**

In `Sources/App/AppDelegate.swift`, `createSnapshot()` builds `leafDirectories` by walking leaves. Build the color map in the same loop and pass it through:

```swift
            var dirs: [UUID: String] = [:]
            var colors: [UUID: PaneTint] = [:]
            for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                if let dir = tab.effectiveSurfaceDirectories[leaf.surfaceID] {
                    dirs[leaf.id] = dir
                }
                if let tint = tab.surfaceColorOverrides[leaf.surfaceID] {
                    colors[leaf.id] = tint
                }
            }
```

and add `leafColorOverrides: colors` to the `TabSnapshot(...)` initializer call.

In `restoreSplitNode`, thread the colors through alongside `directories` and re-key them from leaf ID onto the fresh surface ID:

```swift
    private func restoreSplitNode(
        _ node: SplitNode,
        directories: [UUID: String],
        colors: [UUID: PaneTint],
        app: ghostty_app_t,
        tab: Tab
    ) -> SplitNode {
        switch node {
        case .leaf(let leaf):
```

immediately after `tab.surfaceDirectories[surfaceView.id] = dir`:

```swift
            if let tint = colors[leaf.id] {
                tab.surfaceColorOverrides[surfaceView.id] = tint
            }
```

Pass `colors: colors` at both recursive call sites, and in `restoreSession` call it with `colors: tabSnap.leafColorOverrides`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: session v3 with load-bearing version and store hardening

A newer session is refused rather than partially decoded, an unreadable
file is quarantined before the autosave can overwrite it, and a version
change leaves a backup behind."
```

---

## Task 6: The driving port

Adds the pure command type and the one function that applies it. Nothing calls it yet, so behavior is unchanged.

**Files:**
- Create: `Sources/Control/ControlCommand.swift`
- Create: `Sources/Model/ControlService.swift`
- Test: `Tests/ControlServiceTests.swift`

**Interfaces:**
- Consumes: `PaneTint`, `TintStop`, `ActivityStatus`, `HookStateMachine`, `GitInfo`.
- Produces: `ControlScope`, `ControlCommand`, `ControlError`, `ControlInfo`, `ControlResult`, `SurfaceRef`, `ControlState`, `ControlService.apply(_:target:to:gitInfoProvider:) -> ControlResult`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ControlServiceTests.swift`:

```swift
import Foundation
import Testing

@Suite struct ControlServiceTests {
    private let surfaceID = UUID()
    private let leafID = UUID()
    private let tabID = UUID()

    private func ref(directory: String? = "/Users/ted/montty") -> SurfaceRef {
        SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: leafID,
            tabID: tabID, directory: directory
        )
    }

    private func state() -> ControlState {
        ControlState(
            tabName: "", autoName: "montty/", surfaceColorOverrides: [:],
            tabColorOverride: nil, repoColorOverrides: [:],
            activityStates: [:], activityWaitingSince: [:]
        )
    }

    private let git: (String) -> GitInfo? = { _ in
        GitInfo(
            repoName: "montty", branchName: "main",
            worktreeName: nil, repoPath: "/Users/ted/montty"
        )
    }

    @Test func setsSurfaceColor() {
        var subject = state()
        let tint = PaneTint(stops: [.hex(RGB(r: 1, g: 2, b: 3))])
        let result = ControlService.apply(
            .setColor(scope: .surface, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(result == .applied)
        #expect(subject.surfaceColorOverrides[surfaceID] == tint)
    }

    @Test func setsTabColorAndClearsIt() {
        var subject = state()
        let tint = PaneTint(stops: [.named(.green)])
        _ = ControlService.apply(
            .setColor(scope: .tab, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabColorOverride == tint)

        _ = ControlService.apply(
            .clearColor(scope: .tab),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabColorOverride == nil)
    }

    @Test func setsRepoColorUnderTheRepoIdentity() {
        var subject = state()
        let tint = PaneTint(stops: [.named(.cyan)])
        let result = ControlService.apply(
            .setColor(scope: .repo, tint: tint),
            target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(result == .applied)
        #expect(subject.repoColorOverrides["/Users/ted/montty"] == tint)
    }

    @Test func rejectsRepoScopeOutsideAGitRepo() {
        var subject = state()
        let result = ControlService.apply(
            .setColor(scope: .repo, tint: PaneTint(stops: [.named(.cyan)])),
            target: ref(directory: "/tmp"), to: &subject,
            gitInfoProvider: { _ in nil }
        )
        #expect(result == .rejected(.notInRepo))
        #expect(subject.repoColorOverrides.isEmpty)
    }

    @Test func setsAndClearsTabName() {
        var subject = state()
        _ = ControlService.apply(
            .setName("MR !123"), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabName == "MR !123")

        _ = ControlService.apply(
            .clearName, target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.tabName == "")
    }

    @Test func setsActivityStatusThroughTheHookStateMachine() {
        var subject = state()
        _ = ControlService.apply(
            .setStatus(.waiting), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == .waiting)
        #expect(subject.activityWaitingSince["M1"] != nil)

        _ = ControlService.apply(
            .setStatus(.working), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == .working)
        #expect(subject.activityWaitingSince["M1"] == nil)
    }

    @Test func clearingStatusRemovesTheEntry() {
        var subject = state()
        _ = ControlService.apply(
            .setStatus(.working), target: ref(), to: &subject, gitInfoProvider: git
        )
        _ = ControlService.apply(
            .setStatus(nil), target: ref(), to: &subject, gitInfoProvider: git
        )
        #expect(subject.activityStates["M1"] == nil)
    }

    @Test func infoReportsScopesAndLeavesStateUntouched() {
        var subject = state()
        subject.surfaceColorOverrides[surfaceID] = PaneTint(stops: [.named(.red)])
        subject.repoColorOverrides["/Users/ted/montty"] = PaneTint(stops: [.named(.cyan)])
        let before = subject

        let result = ControlService.apply(
            .info, target: ref(), to: &subject, gitInfoProvider: git
        )

        guard case .read(let info) = result else {
            Issue.record("expected a read result")
            return
        }
        #expect(info.surfaceID == "M1")
        #expect(info.scopes.surface?.stops == ["red"])
        #expect(info.scopes.tab == nil)
        #expect(info.scopes.repo?.identity == "/Users/ted/montty")
        #expect(info.effective?.stops == ["red"])
        #expect(info.tabName == "montty/")
        #expect(info.tabNameIsOverride == false)
        #expect(subject.surfaceColorOverrides == before.surfaceColorOverrides)
        #expect(subject.tabName == before.tabName)
    }

    @Test func infoReportsTheOverriddenNameWhenOneIsSet() {
        var subject = state()
        subject.tabName = "MR !123"
        let result = ControlService.apply(
            .info, target: ref(), to: &subject, gitInfoProvider: git
        )
        guard case .read(let info) = result else {
            Issue.record("expected a read result")
            return
        }
        #expect(info.tabName == "MR !123")
        #expect(info.tabNameIsOverride)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL to compile with `cannot find 'ControlService' in scope`.

- [ ] **Step 3: Define the port vocabulary**

Create `Sources/Control/ControlCommand.swift`:

```swift
// ABOUTME: The driving port: every mutation an outside actor can ask montty
// ABOUTME: for, plus the result and info payload those actors read back.

import Foundation

/// Which layer of the color precedence a command targets.
enum ControlScope: String, Codable, CaseIterable {
    case surface, tab, repo
}

/// The complete set of mutations available to the CLI, the context menu, and
/// the Claude Code hooks.
enum ControlCommand: Equatable {
    case setColor(scope: ControlScope, tint: PaneTint)
    case clearColor(scope: ControlScope)
    case setName(String)
    case clearName
    /// nil clears the entry, matching a hook session-end.
    case setStatus(ActivityStatus.State?)
    case info
}

enum ControlError: String, Codable, Equatable {
    case unknownSurface = "unknown surface"
    case notInRepo = "surface is not inside a git repository"
}

/// Tints are reported as explicit arrays rather than the compact
/// string-or-array session form, so consumers can index without branching.
struct TintPayload: Codable, Equatable {
    let stops: [String]

    init(_ tint: PaneTint) {
        stops = tint.stops.map(\.text)
    }
}

struct RepoTintPayload: Codable, Equatable {
    let identity: String
    let stops: [String]
}

struct ControlInfo: Codable, Equatable {
    struct Scopes: Codable, Equatable {
        let surface: TintPayload?
        let tab: TintPayload?
        let repo: RepoTintPayload?
    }

    struct Git: Codable, Equatable {
        let repoName: String
        let branch: String?
        let worktree: String?
        let repoPath: String
    }

    let surfaceID: String
    let leafID: String
    let tabID: String
    let tabName: String
    let tabNameIsOverride: Bool
    let scopes: Scopes
    let effective: TintPayload?
    let git: Git?
    let status: String?
}

enum ControlResult: Equatable {
    case applied
    case read(ControlInfo)
    case rejected(ControlError)
}
```

- [ ] **Step 4: Write the application core**

Create `Sources/Model/ControlService.swift`:

```swift
// ABOUTME: The one place styling and activity state is mutated, shared by the
// ABOUTME: montty CLI, the tab context menu, and the Claude Code hooks.

import Foundation

/// Identifies the surface a command targets. Adapters build this by resolving
/// a MONTTY_SURFACE_ID against the tab store, so ControlService never walks it.
struct SurfaceRef: Equatable {
    let monttyID: String
    let surfaceID: UUID
    let leafID: UUID
    let tabID: UUID
    /// Claude's reported cwd when present, otherwise the shell pwd.
    let directory: String?
}

/// A narrow view of exactly what a control command may change.
struct ControlState: Equatable {
    var tabName: String
    var autoName: String
    var surfaceColorOverrides: [UUID: PaneTint]
    var tabColorOverride: PaneTint?
    var repoColorOverrides: [String: PaneTint]
    var activityStates: [String: ActivityStatus.State]
    var activityWaitingSince: [String: Date]
}

enum ControlService {
    static func apply(
        _ command: ControlCommand,
        target: SurfaceRef,
        to state: inout ControlState,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:),
        now: Date = Date()
    ) -> ControlResult {
        switch command {
        case .setColor(let scope, let tint):
            return setColor(scope, tint, target: target, to: &state,
                            gitInfoProvider: gitInfoProvider)

        case .clearColor(let scope):
            return setColor(scope, nil, target: target, to: &state,
                            gitInfoProvider: gitInfoProvider)

        case .setName(let name):
            state.tabName = name
            return .applied

        case .clearName:
            state.tabName = ""
            return .applied

        case .setStatus(let status):
            let event: ClaudeHookEvent
            switch status {
            case .working: event = .promptSubmit
            case .waiting: event = .notification
            case .idle: event = .stop
            case nil: event = .sessionEnd
            }
            _ = HookStateMachine.apply(
                event,
                surfaceID: target.monttyID,
                to: &state.activityStates,
                waitingSince: &state.activityWaitingSince,
                isKnownSurface: true,
                now: now
            )
            return .applied

        case .info:
            return .read(info(target: target, state: state,
                              gitInfoProvider: gitInfoProvider))
        }
    }

    /// A nil tint clears that scope. Repo scope needs a git identity, so it is
    /// the only scope that can be rejected.
    private static func setColor(
        _ scope: ControlScope,
        _ tint: PaneTint?,
        target: SurfaceRef,
        to state: inout ControlState,
        gitInfoProvider: (String) -> GitInfo?
    ) -> ControlResult {
        switch scope {
        case .surface:
            state.surfaceColorOverrides[target.surfaceID] = tint
        case .tab:
            state.tabColorOverride = tint
        case .repo:
            guard let identity = repoIdentity(target: target,
                                              gitInfoProvider: gitInfoProvider) else {
                return .rejected(.notInRepo)
            }
            state.repoColorOverrides[identity] = tint
        }
        return .applied
    }

    private static func repoIdentity(
        target: SurfaceRef,
        gitInfoProvider: (String) -> GitInfo?
    ) -> String? {
        guard let directory = target.directory,
              let info = gitInfoProvider(directory) else { return nil }
        return info.repoPath + (info.worktreeName ?? "")
    }

    private static func info(
        target: SurfaceRef,
        state: ControlState,
        gitInfoProvider: (String) -> GitInfo?
    ) -> ControlInfo {
        let gitInfo = target.directory.flatMap(gitInfoProvider)
        let identity = gitInfo.map { $0.repoPath + ($0.worktreeName ?? "") }
        let repoTint = identity.flatMap { state.repoColorOverrides[$0] }

        let effective = TabColor.resolvedPaneTint(
            surfaceOverride: state.surfaceColorOverrides[target.surfaceID],
            tabColorOverride: state.tabColorOverride,
            surfaceDirectory: target.directory,
            repoColorOverrides: state.repoColorOverrides
        )

        return ControlInfo(
            surfaceID: target.monttyID,
            leafID: target.leafID.uuidString,
            tabID: target.tabID.uuidString,
            tabName: state.tabName.isEmpty ? state.autoName : state.tabName,
            tabNameIsOverride: !state.tabName.isEmpty,
            scopes: ControlInfo.Scopes(
                surface: state.surfaceColorOverrides[target.surfaceID].map(TintPayload.init),
                tab: state.tabColorOverride.map(TintPayload.init),
                repo: zip2(identity, repoTint).map {
                    RepoTintPayload(identity: $0, stops: $1.stops.map(\.text))
                }
            ),
            effective: effective.map(TintPayload.init),
            git: gitInfo.map {
                ControlInfo.Git(
                    repoName: $0.repoName, branch: $0.branchName,
                    worktree: $0.worktreeName, repoPath: $0.repoPath
                )
            },
            status: state.activityStates[target.monttyID].map { String(describing: $0) }
        )
    }

    /// Pair two optionals, yielding nil unless both are present.
    private static func zip2<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
        guard let first, let second else { return nil }
        return (first, second)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add the ControlService driving port

One function owns precedence and validation, so the CLI, the context
menu, and the Claude hooks cannot drift apart."
```

---

## Task 7: Route the context menu through the port

The menu's two color entries look identical but write different scopes. This makes all three scopes explicit and makes every one of them the same write path the CLI will use, so the menu's Reset clears anything `montty` set.

**Files:**
- Modify: `Sources/View/TabContextMenu.swift`
- Modify: `Sources/View/TabSidebar.swift`
- Modify: `Sources/App/MainWindow.swift`
- Modify: `Sources/App/AppDelegate.swift` (add the adapter entry point)
- Test: `Tests/ControlAdapterTests.swift`

**Interfaces:**
- Consumes: `ControlCommand`, `ControlService`, `SurfaceRef` from Task 6.
- Produces: `AppDelegate.applyControl(_ command: ControlCommand, to tab: Tab) -> ControlResult`, and `AppDelegate.surfaceRef(for surfaceID: UUID, in tab: Tab) -> SurfaceRef?`. `TabContextMenu` takes a single `onControl: (ControlCommand) -> Void` closure in place of `onSetRepoColor` and `onSetTabColor`.

This task's deliverable is AppKit UI, which the test target cannot reach. There is no honest failing unit test for a SwiftUI menu, so the gate here is the manual check in Step 6. The test below is regression coverage for the state round-trip the adapter performs, and it will pass as soon as it compiles because Task 6 already built the port. Write it anyway: it is what catches a later change to `ControlState`'s shape.

- [ ] **Step 1: Write the adapter round-trip test**

Create `Tests/ControlAdapterTests.swift`. This exercises the state round-trip that the menu adapter performs, without AppKit:

```swift
import Foundation
import Testing

@Suite struct ControlAdapterTests {
    @Test func menuStyleClearRemovesACLISetGradient() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        let ref = SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: UUID(),
            tabID: tab.id, directory: nil
        )

        var state = ControlState(
            tabName: tab.name, autoName: tab.autoName,
            surfaceColorOverrides: tab.surfaceColorOverrides,
            tabColorOverride: tab.colorOverride,
            repoColorOverrides: [:], activityStates: [:], activityWaitingSince: [:]
        )

        let gradient = PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        _ = ControlService.apply(
            .setColor(scope: .surface, tint: gradient), target: ref, to: &state
        )
        #expect(state.surfaceColorOverrides[surfaceID] == gradient)

        _ = ControlService.apply(.clearColor(scope: .surface), target: ref, to: &state)
        #expect(state.surfaceColorOverrides[surfaceID] == nil)
    }

    @Test func stateWritesBackOntoTheTab() {
        let surfaceID = UUID()
        let tab = Tab(surfaceID: surfaceID)
        var state = ControlState(
            tabName: "", autoName: "", surfaceColorOverrides: [:],
            tabColorOverride: nil, repoColorOverrides: [:],
            activityStates: [:], activityWaitingSince: [:]
        )
        let ref = SurfaceRef(
            monttyID: "M1", surfaceID: surfaceID, leafID: UUID(),
            tabID: tab.id, directory: nil
        )

        _ = ControlService.apply(.setName("MR !123"), target: ref, to: &state)
        tab.name = state.tabName
        tab.surfaceColorOverrides = state.surfaceColorOverrides
        tab.colorOverride = state.tabColorOverride

        #expect(tab.displayName == "MR !123")
    }
}
```

- [ ] **Step 2: Run the test**

Run: `just test`
Expected: PASS. If it fails to compile, `ControlState`'s member list drifted from Task 6; fix that before wiring the menu.

- [ ] **Step 3: Add the adapter to AppDelegate**

In `Sources/App/AppDelegate.swift`, add:

```swift
    /// Resolve a surface to the reference ControlService needs.
    func surfaceRef(for surfaceID: UUID, in tab: Tab) -> SurfaceRef? {
        guard let monttyID = tab.surfaceToMonttyID[surfaceID],
              let leaf = SplitTree.findLeaf(node: tab.splitRoot, surfaceID: surfaceID)
        else { return nil }
        return SurfaceRef(
            monttyID: monttyID,
            surfaceID: surfaceID,
            leafID: leaf.id,
            tabID: tab.id,
            directory: tab.effectiveSurfaceDirectories[surfaceID]
        )
    }

    /// The single write path into styling state. Every driving adapter -- the
    /// CLI, the context menu, and the Claude hooks -- comes through here.
    @discardableResult
    func applyControl(_ command: ControlCommand, to tab: Tab, surfaceID: UUID) -> ControlResult {
        guard let target = surfaceRef(for: surfaceID, in: tab) else {
            return .rejected(.unknownSurface)
        }
        var state = ControlState(
            tabName: tab.name,
            autoName: tab.autoName,
            surfaceColorOverrides: tab.surfaceColorOverrides,
            tabColorOverride: tab.colorOverride,
            repoColorOverrides: repoColorOverrides,
            activityStates: tab.activityStates,
            activityWaitingSince: tab.activityWaitingSince
        )
        let result = ControlService.apply(command, target: target, to: &state)
        tab.name = state.tabName
        tab.surfaceColorOverrides = state.surfaceColorOverrides
        tab.colorOverride = state.tabColorOverride
        tab.activityStates = state.activityStates
        tab.activityWaitingSince = state.activityWaitingSince
        repoColorOverrides = state.repoColorOverrides
        return result
    }
```

- [ ] **Step 4: Rewrite the context menu with three labeled scopes**

Replace `Sources/View/TabContextMenu.swift`:

```swift
import SwiftUI

struct TabContextMenu: View {
    let tab: Tab
    var repoColorOverrides: [String: PaneTint] = [:]
    let onRename: () -> Void
    let onControl: (ControlCommand) -> Void
    let onClose: () -> Void

    /// The focused surface's directory, if any. Prefers Claude-reported cwd
    /// over the parent shell's pwd so the menu reflects the active worktree.
    private var focusedDir: String? {
        tab.focusedSurfaceID.flatMap { tab.effectiveSurfaceDirectories[$0] }
    }

    private var focusedGitInfo: GitInfo? {
        focusedDir.flatMap { GitInfo.from(path: $0) }
    }

    private var repoIdentity: String? {
        guard let info = focusedGitInfo else { return nil }
        return info.repoPath + (info.worktreeName ?? "")
    }

    private var repoColorLabel: String {
        guard let info = focusedGitInfo else { return "Repo Color" }
        if let worktree = info.worktreeName {
            return "Repo Color: \(info.repoName) (\(worktree))"
        }
        return "Repo Color: \(info.repoName)"
    }

    private var surfaceOverride: PaneTint? {
        tab.focusedSurfaceID.flatMap { tab.surfaceColorOverrides[$0] }
    }

    /// The swatch to check in a submenu. A gradient or hex tint matches no
    /// named swatch, so nothing shows checked and only Reset applies.
    private func swatch(for override: PaneTint?, fallback: TintStop) -> TintStop {
        guard let override, !override.isGradient else { return override?.primary ?? fallback }
        return override.primary
    }

    var body: some View {
        Button("Rename...") { onRename() }

        Menu("Surface Color") {
            TabColorPicker(
                currentColor: swatch(
                    for: surfaceOverride,
                    fallback: tab.effectiveColor(overrides: repoColorOverrides)
                ),
                hasOverride: surfaceOverride != nil,
                onSelect: { tint in
                    onControl(tint.map { .setColor(scope: .surface, tint: $0) }
                        ?? .clearColor(scope: .surface))
                }
            )
        }

        Menu("Tab Color") {
            TabColorPicker(
                currentColor: swatch(
                    for: tab.colorOverride,
                    fallback: tab.effectiveColor(overrides: repoColorOverrides)
                ),
                hasOverride: tab.colorOverride != nil,
                onSelect: { tint in
                    onControl(tint.map { .setColor(scope: .tab, tint: $0) }
                        ?? .clearColor(scope: .tab))
                }
            )
        }

        if let identity = repoIdentity {
            let override = repoColorOverrides[identity]
            Menu(repoColorLabel) {
                TabColorPicker(
                    currentColor: swatch(
                        for: override,
                        fallback: .named(TabColor.colorForWorktree(focusedDir) ?? .gray)
                    ),
                    hasOverride: override != nil,
                    onSelect: { tint in
                        onControl(tint.map { .setColor(scope: .repo, tint: $0) }
                            ?? .clearColor(scope: .repo))
                    }
                )
            }
        }

        Divider()

        Button("Close Tab") { onClose() }
    }
}
```

- [ ] **Step 5: Rewire the callers**

In `Sources/View/TabSidebar.swift`, replace the two color closures with one:

```swift
    let onControl: (Tab, ControlCommand) -> Void
```

and at the `TabContextMenu` construction site (around `TabSidebar.swift:59`):

```swift
                                    onControl: { command in
                                        onControl(tab, command)
                                    },
```

In `Sources/App/MainWindow.swift`, replace the `onSetTabColor` / `onSetRepoColor` wiring (around `MainWindow.swift:24`) with:

```swift
                    onControl: { tab, command in
                        guard let surfaceID = tab.focusedSurfaceID else { return }
                        appDelegate.applyControl(command, to: tab, surfaceID: surfaceID)
                    },
```

Delete any now-unused `onSetRepoColor` / `onSetTabColor` declarations from `TabSidebar` and `MainWindow`.

- [ ] **Step 6: Run tests and verify the menu by hand**

Run: `just check`
Expected: PASS.

Then verify the three scopes are actually distinct:

```bash
just run-bg
just inspect-surfaces | jq '.[] | {id, tab_name, tab_color}'
```

Right-click a tab. Confirm the menu reads `Surface Color`, `Tab Color`, and `Repo Color: <repo>`; that setting a Surface Color tints only the focused pane; that setting a Tab Color tints the other panes but not the one with a surface override; and that each Reset appears only when that scope is set. Then `just stop`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: three labeled color scopes in the tab context menu

Surface, tab, and repo each get their own submenu and Reset, and all
three write through ControlService so the menu can clear anything the
CLI set."
```

---

## Task 8: The wire format

Pure request and response types. Nothing sends them yet.

**Files:**
- Create: `Sources/Control/ControlWire.swift`
- Test: `Tests/ControlWireTests.swift`

**Interfaces:**
- Consumes: `ControlCommand`, `ControlScope`, `PaneTint`, `ControlInfo`.
- Produces: `ControlWire.version == 1`; `ControlRequest` with `init?(json: Data)`, `var command: ControlCommand?`, `var surface: String`, `func encoded() throws -> Data`; `ControlRequest.DecodeFailure` with `.malformed`, `.unsupportedVersion`, `.legacyHook`; `ControlResponse.ok`, `.failure(String)`, `.info(ControlInfo)` with `func encoded() throws -> Data`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ControlWireTests.swift`:

```swift
import Foundation
import Testing

@Suite struct ControlWireTests {
    @Test func decodesASetColorRequest() throws {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"surface",
         "prop":"color","value":["neutralBright","#1a7f37"]}
        """.utf8)
        let request = try ControlRequest.decode(json)
        #expect(request.surface == "M1")
        #expect(request.command == .setColor(
            scope: .surface,
            tint: PaneTint(stops: [.named(.neutralBright), .hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        ))
    }

    @Test func aNullValueIsTheClearForm() throws {
        let json = Data("""
        {"v":1,"cmd":"set","surface":"M1","scope":"tab","prop":"color","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(json).command == .clearColor(scope: .tab))
    }

    @Test func decodesNameAndStatus() throws {
        let name = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"name","value":"MR !123"}
        """.utf8)
        #expect(try ControlRequest.decode(name).command == .setName("MR !123"))

        let clear = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"name","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(clear).command == .clearName)

        let status = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"status","value":"waiting"}
        """.utf8)
        #expect(try ControlRequest.decode(status).command == .setStatus(.waiting))

        let cleared = Data("""
        {"v":1,"cmd":"set","surface":"M1","prop":"status","value":null}
        """.utf8)
        #expect(try ControlRequest.decode(cleared).command == .setStatus(nil))
    }

    @Test func decodesInfo() throws {
        let json = Data("{\"v\":1,\"cmd\":\"info\",\"surface\":\"M1\"}".utf8)
        #expect(try ControlRequest.decode(json).command == .info)
    }

    @Test func rejectsANewerProtocolVersion() {
        let json = Data("{\"v\":2,\"cmd\":\"info\",\"surface\":\"M1\"}".utf8)
        #expect(throws: ControlRequest.DecodeFailure.unsupportedVersion) {
            try ControlRequest.decode(json)
        }
    }

    @Test func aMessageWithNoCmdIsALegacyHook() {
        let json = Data("{\"event\":\"stop\",\"surface\":\"M1\",\"cwd\":\"/tmp\"}".utf8)
        #expect(throws: ControlRequest.DecodeFailure.legacyHook) {
            try ControlRequest.decode(json)
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: ControlRequest.DecodeFailure.malformed) {
            try ControlRequest.decode(Data("{ not json".utf8))
        }
    }

    @Test func requestRoundTripsThroughEncoding() throws {
        let request = ControlRequest(
            surface: "M1",
            command: .setColor(scope: .repo, tint: PaneTint(stops: [.named(.cyan)]))
        )
        let decoded = try ControlRequest.decode(try request.encoded())
        #expect(decoded.command == request.command)
        #expect(decoded.surface == "M1")
    }

    @Test func encodesResponses() throws {
        let ok = String(data: try ControlResponse.ok.encoded(), encoding: .utf8)
        #expect(ok == "{\"ok\":true}")

        let failure = try ControlResponse.failure("unknown surface").encoded()
        let parsed = try JSONSerialization.jsonObject(with: failure) as? [String: Any]
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "unknown surface")
    }

    @Test func infoResponseCarriesOkAlongsideSnakeCasedFields() throws {
        let info = ControlInfo(
            surfaceID: "M1", leafID: "L1", tabID: "T1",
            tabName: "montty/", tabNameIsOverride: false,
            scopes: ControlInfo.Scopes(surface: nil, tab: nil, repo: nil),
            effective: TintPayload(PaneTint(stops: [.named(.green)])),
            git: nil, status: nil
        )
        let data = try ControlResponse.info(info).encoded()
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["surface_id"] as? String == "M1")
        #expect(parsed?["tab_name_is_override"] as? Bool == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL to compile with `cannot find 'ControlRequest' in scope`.

- [ ] **Step 3: Write the wire types**

Create `Sources/Control/ControlWire.swift`:

```swift
// ABOUTME: JSON envelope for the montty control socket: one versioned request
// ABOUTME: per connection, one response, then close.

import Foundation

enum ControlWire {
    /// Bumped only when the envelope shape changes incompatibly.
    static let version = 1
}

/// One request carries exactly one command, matching one ControlCommand.
struct ControlRequest: Equatable {
    let surface: String
    let command: ControlCommand

    enum DecodeFailure: Error, Equatable {
        case malformed
        case unsupportedVersion
        /// No `cmd` field: a hook event from the shell wrapper, which the
        /// legacy ClaudeHookMessage path still owns.
        case legacyHook
    }

    static func decode(_ data: Data) throws -> ControlRequest {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            throw DecodeFailure.malformed
        }
        guard let cmd = root["cmd"] as? String else {
            throw DecodeFailure.legacyHook
        }
        guard ((root["v"] as? Int) ?? 0) <= ControlWire.version else {
            throw DecodeFailure.unsupportedVersion
        }
        guard let surface = root["surface"] as? String, !surface.isEmpty else {
            throw DecodeFailure.malformed
        }

        switch cmd {
        case "info":
            return ControlRequest(surface: surface, command: .info)
        case "set":
            return ControlRequest(
                surface: surface,
                command: try setCommand(root)
            )
        default:
            throw DecodeFailure.malformed
        }
    }

    private static func setCommand(_ root: [String: Any]) throws -> ControlCommand {
        guard let prop = root["prop"] as? String else { throw DecodeFailure.malformed }
        // NSNull is how JSONSerialization reports an explicit null, which is
        // the clear form. A missing key is malformed, not a clear.
        guard root.keys.contains("value") else { throw DecodeFailure.malformed }
        let value = root["value"]
        let isNull = value == nil || value is NSNull

        switch prop {
        case "color":
            let scope = ControlScope(rawValue: root["scope"] as? String ?? "")
            guard let scope else { throw DecodeFailure.malformed }
            if isNull { return .clearColor(scope: scope) }
            guard let texts = value as? [String] else { throw DecodeFailure.malformed }
            let stops = texts.compactMap(TintStop.parse)
            guard stops.count == texts.count, !stops.isEmpty,
                  stops.count <= PaneTint.maxStops else {
                throw DecodeFailure.malformed
            }
            return .setColor(scope: scope, tint: PaneTint(stops: stops))

        case "name":
            if isNull { return .clearName }
            guard let name = value as? String else { throw DecodeFailure.malformed }
            return .setName(name)

        case "status":
            if isNull { return .setStatus(nil) }
            guard let text = value as? String else { throw DecodeFailure.malformed }
            switch text {
            case "working": return .setStatus(.working)
            case "waiting": return .setStatus(.waiting)
            case "idle": return .setStatus(.idle)
            default: throw DecodeFailure.malformed
            }

        default:
            throw DecodeFailure.malformed
        }
    }

    func encoded() throws -> Data {
        var root: [String: Any] = ["v": ControlWire.version, "surface": surface]
        switch command {
        case .info:
            root["cmd"] = "info"
        case .setColor(let scope, let tint):
            root["cmd"] = "set"
            root["prop"] = "color"
            root["scope"] = scope.rawValue
            root["value"] = tint.stops.map(\.text)
        case .clearColor(let scope):
            root["cmd"] = "set"
            root["prop"] = "color"
            root["scope"] = scope.rawValue
            root["value"] = NSNull()
        case .setName(let name):
            root["cmd"] = "set"
            root["prop"] = "name"
            root["value"] = name
        case .clearName:
            root["cmd"] = "set"
            root["prop"] = "name"
            root["value"] = NSNull()
        case .setStatus(let status):
            root["cmd"] = "set"
            root["prop"] = "status"
            root["value"] = status.map { String(describing: $0) } ?? NSNull()
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }
}

enum ControlResponse {
    case ok
    case failure(String)
    case info(ControlInfo)

    func encoded() throws -> Data {
        switch self {
        case .ok:
            return try JSONSerialization.data(
                withJSONObject: ["ok": true], options: [.sortedKeys]
            )
        case .failure(let message):
            return try JSONSerialization.data(
                withJSONObject: ["ok": false, "error": message], options: [.sortedKeys]
            )
        case .info(let info):
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(info)
            guard var root = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
                return try ControlResponse.failure("info encoding failed").encoded()
            }
            root["ok"] = true
            return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: versioned request and response envelope for the control socket

A message with no cmd field still routes to the legacy hook path, so an
older shell wrapper keeps working."
```

---

## Task 9: Serve control requests over the socket

**The socket relocation in Steps 1, 2, and 4 already landed** in commit
`bc6feb4`, pulled forward because the hardcoded `/tmp/montty-hook.sock` meant
every dev build launched for a manual check stole the installed app's socket and
left the user's real montty unable to receive hook events until restarted. That
commit changed `HookServer.socketPath` to honor `MONTTY_SOCKET`, updated the
file's ABOUTME lines, and set `MONTTY_SOCKET` in the `justfile`'s `run` and
`run-bg` recipes. Skip those steps; verify them rather than redoing them.

What remains here is the request handling: concurrent per-connection dispatch,
decoding a `ControlRequest`, routing it through `AppDelegate.applyControl`, and
writing a response before closing.

**Files:**
- Modify: `Sources/App/HookServer.swift` (accept loop, connection handling, reply)
- Test: manual, via `just inspect-*` and `nc`

**Interfaces:**
- Consumes: `ControlRequest`, `ControlResponse` from Task 8; `AppDelegate.applyControl` from Task 7.
- Produces: `HookServer.socketPath` honoring `MONTTY_SOCKET`; per-connection handling on a concurrent queue; a JSON response written before close.

- [ ] **Step 1: Relocate the socket**

In `Sources/App/HookServer.swift`, replace the constant:

```swift
    /// Per-user, mode 0700, and auto-cleaned. `MONTTY_SOCKET` overrides it so a
    /// dev build never rebinds the installed app's socket, mirroring
    /// MONTTY_SESSION_DIR.
    static let socketPath = ProcessInfo.processInfo.environment["MONTTY_SOCKET"]
        ?? NSTemporaryDirectory() + "montty-hook.sock"
```

`AppDelegate` already injects `HookServer.socketPath` as `MONTTY_SOCKET` at `AppDelegate.swift:178`, `:248`, and `:594`, so panes automatically get the resolved path with no further change.

- [ ] **Step 2: Verify the relocation by hand**

Run:

```bash
just generate && just build
MONTTY_SESSION_DIR=/tmp/montty-build/session \
MONTTY_SOCKET=/tmp/montty-build/hook.sock \
  /tmp/montty-build/Debug/Montty.app/Contents/MacOS/Montty &
sleep 3
ls -l /tmp/montty-build/hook.sock
```

Expected: the socket exists at the override path. Confirm the default path is used without the override:

```bash
just stop
just run-bg
ls -l "$(getconf DARWIN_USER_TEMP_DIR)montty-hook.sock"
just stop
```

Expected: the socket exists under `/var/folders/...`.

- [ ] **Step 3: Handle each connection concurrently and reply**

In `Sources/App/HookServer.swift`, replace `acceptLoop` and `processHook` with a version that dispatches per connection and writes a response. The accept loop must not block, because `info` waits on a main-thread hop.

```swift
    private static let handlerQueue = DispatchQueue(
        label: "montty.hookserver.handler", attributes: .concurrent
    )

    private static func acceptLoop() {
        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            handlerQueue.async { handleConnection(clientFD) }
        }
    }

    private static func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        var buffer = [UInt8](repeating: 0, count: 65_536)
        let bytesRead = read(clientFD, &buffer, buffer.count)
        guard bytesRead > 0 else { return }
        let data = Data(buffer[..<bytesRead])

        let response: ControlResponse
        do {
            let request = try ControlRequest.decode(data)
            response = applyOnMain(request)
        } catch ControlRequest.DecodeFailure.legacyHook {
            processHook(String(decoding: data, as: UTF8.self))
            return
        } catch ControlRequest.DecodeFailure.unsupportedVersion {
            response = .failure("montty CLI is newer than the app")
        } catch {
            response = .failure("malformed request")
        }

        if let out = try? response.encoded() {
            out.withUnsafeBytes { _ = write(clientFD, $0.baseAddress, $0.count) }
        }
    }

    /// Model mutation happens on main. A 2s ceiling keeps a wedged main thread
    /// from pinning a handler thread forever.
    private static func applyOnMain(_ request: ControlRequest) -> ControlResponse {
        let semaphore = DispatchSemaphore(value: 0)
        var response: ControlResponse = .failure("montty did not respond")

        DispatchQueue.main.async {
            defer { semaphore.signal() }
            guard let appDelegate = findAppDelegate(),
                  let tab = appDelegate.tabStore.tabs.first(where: { tab in
                      tab.surfaceToMonttyID.values.contains(request.surface)
                  }),
                  let surfaceID = tab.surfaceToMonttyID.first(
                      where: { $0.value == request.surface }
                  )?.key else {
                response = .failure(ControlError.unknownSurface.rawValue)
                return
            }
            switch appDelegate.applyControl(request.command, to: tab, surfaceID: surfaceID) {
            case .applied: response = .ok
            case .read(let info): response = .info(info)
            case .rejected(let error): response = .failure(error.rawValue)
            }
        }

        if semaphore.wait(timeout: .now() + 2) == .timedOut {
            return .failure("montty did not respond")
        }
        return response
    }
```

Keep `processHook` exactly as it is. It is now reached only through the `legacyHook` branch.

- [ ] **Step 4: Isolate the dev build's socket**

In `justfile`, add the socket override to both run recipes so a dev build cannot rebind the installed app's socket:

```make
# Build and launch the app (foreground)
# MONTTY_SESSION_DIR and MONTTY_SOCKET keep this build's tabs and hook socket
# out of the installed app's
run: build
    MONTTY_SESSION_DIR={{build_dir}}/session MONTTY_SOCKET={{build_dir}}/hook.sock {{build_dir}}/Debug/Montty.app/Contents/MacOS/Montty

# Build and launch the app (background, for scripted testing)
run-bg: build
    @MONTTY_SESSION_DIR={{build_dir}}/session MONTTY_SOCKET={{build_dir}}/hook.sock {{build_dir}}/Debug/Montty.app/Contents/MacOS/Montty &
    @sleep 2
    @echo "Montty launched in background. Use 'just stop' to quit."
```

- [ ] **Step 5: Verify request handling end to end**

`inspect-surfaces` reports the Ghostty surface UUID, not the `MONTTY_SURFACE_ID` the socket keys on. Read the montty id out of a pane instead:

```bash
just run-bg
just inspect-type 'echo $MONTTY_SURFACE_ID' && just inspect-key return
sleep 1
MID=$(just inspect-screen | jq -r .text | tail -3 | grep -E '^[0-9A-F-]{36}$' | tail -1)

printf '{"v":1,"cmd":"set","surface":"%s","scope":"tab","prop":"color","value":["neutralBright","#1a7f37"]}' "$MID" \
  | nc -U /tmp/montty-build/hook.sock -w 1
```

Expected: `{"ok":true}` and the tab visibly turns into a white-to-green gradient.

```bash
printf '{"v":1,"cmd":"info","surface":"%s"}' "$MID" \
  | nc -U /tmp/montty-build/hook.sock -w 1 | jq .
```

Expected: `ok: true`, `tab_name`, and `scopes.tab.stops` reading `["neutralBright","#1a7f37"]`.

```bash
printf '{"v":9,"cmd":"info","surface":"%s"}' "$MID" \
  | nc -U /tmp/montty-build/hook.sock -w 1
printf '{"v":1,"cmd":"info","surface":"nope"}' \
  | nc -U /tmp/montty-build/hook.sock -w 1
just stop
```

Expected: `montty CLI is newer than the app`, then `unknown surface`.

- [ ] **Step 6: Confirm the legacy hook path still works**

```bash
just run-bg
just inspect-type 'claude' && just inspect-key return
sleep 5
just inspect-hook-log | jq '.[-3:]'
```

Expected: `session-start` events with `matched: true`. Then `just stop`.

- [ ] **Step 7: Run the suite and commit**

Run: `just check`
Expected: PASS.

```bash
git add -A
git commit -m "feat: serve control requests over the relocated hook socket

The socket moves to the per-user temp dir, so a dev build no longer
rebinds the installed app's path and unlinks it out from under real
panes. Connections are handled concurrently now that a reply can wait on
the main thread."
```

---

## Task 10: Argument parsing

Pure argv-to-command translation, shared by the binary and its tests.

**Files:**
- Create: `Sources/Control/ControlArgs.swift`
- Test: `Tests/ControlArgsTests.swift`

**Interfaces:**
- Consumes: `ControlCommand`, `ControlScope`, `PaneTint`, `TintStop`.
- Produces: `ControlArgs.parse(_ arguments: [String]) -> Result<ParsedInvocation, ControlArgs.UsageError>`; `enum ParsedInvocation { case control(ControlCommand); case hook(String); case version }`; `ControlArgs.usage: String`.

Arguments exclude the executable name. `ControlArgs` never touches the environment or the network.

- [ ] **Step 1: Write the failing test**

Create `Tests/ControlArgsTests.swift`:

```swift
import Foundation
import Testing

@Suite struct ControlArgsTests {
    private func command(_ args: [String]) -> ControlCommand? {
        guard case .success(.control(let command)) = ControlArgs.parse(args) else { return nil }
        return command
    }

    private func failure(_ args: [String]) -> ControlArgs.UsageError? {
        guard case .failure(let error) = ControlArgs.parse(args) else { return nil }
        return error
    }

    @Test func parsesSingleColorForEachScope() {
        #expect(command(["surface", "color", "#1a7f37"]) == .setColor(
            scope: .surface, tint: PaneTint(stops: [.hex(RGB(r: 0x1A, g: 0x7F, b: 0x37))])
        ))
        #expect(command(["tab", "color", "green"]) == .setColor(
            scope: .tab, tint: PaneTint(stops: [.named(.green)])
        ))
        #expect(command(["repo", "color", "cyan"]) == .setColor(
            scope: .repo, tint: PaneTint(stops: [.named(.cyan)])
        ))
    }

    @Test func parsesTwoAndThreeStopGradients() {
        #expect(command(["surface", "color", "neutralBright,green"]) == .setColor(
            scope: .surface,
            tint: PaneTint(stops: [.named(.neutralBright), .named(.green)])
        ))
        #expect(command(["tab", "color", "blue,brightMagenta,cyan"]) == .setColor(
            scope: .tab,
            tint: PaneTint(stops: [.named(.blue), .named(.brightMagenta), .named(.cyan)])
        ))
    }

    @Test func parsesResetForEachScope() {
        #expect(command(["surface", "color", "--reset"]) == .clearColor(scope: .surface))
        #expect(command(["tab", "color", "--reset"]) == .clearColor(scope: .tab))
        #expect(command(["repo", "color", "--reset"]) == .clearColor(scope: .repo))
    }

    @Test func parsesNameAndReset() {
        #expect(command(["tab", "name", "MR !123 fix auth"]) == .setName("MR !123 fix auth"))
        #expect(command(["tab", "name", "--reset"]) == .clearName)
    }

    @Test func parsesStatus() {
        #expect(command(["surface", "status", "working"]) == .setStatus(.working))
        #expect(command(["surface", "status", "waiting"]) == .setStatus(.waiting))
        #expect(command(["surface", "status", "idle"]) == .setStatus(.idle))
        #expect(command(["surface", "status", "clear"]) == .setStatus(nil))
    }

    @Test func parsesInfoAndVersion() {
        #expect(command(["info"]) == .info)
        guard case .success(.version) = ControlArgs.parse(["--version"]) else {
            Issue.record("expected version")
            return
        }
    }

    @Test func parsesHook() {
        guard case .success(.hook(let event)) = ControlArgs.parse(["hook", "pre-tool-use"]) else {
            Issue.record("expected hook")
            return
        }
        #expect(event == "pre-tool-use")
    }

    @Test func rejectsBadColorSpecs() {
        #expect(failure(["tab", "color", "chartreuse"]) == .badColor("chartreuse"))
        #expect(failure(["tab", "color", "#fff"]) == .badColor("#fff"))
        #expect(failure(["tab", "color", "red,green,blue,cyan"]) == .tooManyStops)
        #expect(failure(["tab", "color", ""]) == .badColor(""))
    }

    @Test func rejectsUnknownScopesVerbsAndStatuses() {
        #expect(failure(["window", "color", "red"]) == .unknownScope("window"))
        #expect(failure(["tab", "opacity", "0.5"]) == .unknownProperty("opacity"))
        #expect(failure(["surface", "status", "thinking"]) == .unknownStatus("thinking"))
        #expect(failure(["surface", "name", "x"]) == .unknownProperty("name"))
        #expect(failure(["tab", "status", "idle"]) == .unknownProperty("status"))
        #expect(failure([]) == .noArguments)
    }

    @Test func rejectsAMissingValue() {
        #expect(failure(["tab", "color"]) == .missingValue("color"))
        #expect(failure(["tab", "name"]) == .missingValue("name"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `just test`
Expected: FAIL to compile with `cannot find 'ControlArgs' in scope`.

- [ ] **Step 3: Write the parser**

Create `Sources/Control/ControlArgs.swift`:

```swift
// ABOUTME: Translates montty's argv into a ControlCommand without touching the
// ABOUTME: environment or the network, so the whole grammar is unit-testable.

import Foundation

enum ParsedInvocation: Equatable {
    case control(ControlCommand)
    /// A Claude Code hook event name, forwarded on the legacy wire format.
    case hook(String)
    case version
}

enum ControlArgs {
    enum UsageError: Error, Equatable {
        case noArguments
        case unknownScope(String)
        case unknownProperty(String)
        case unknownStatus(String)
        case missingValue(String)
        case badColor(String)
        case tooManyStops
    }

    static let usage = """
        usage: montty <scope> <property> <value>

          montty surface color <spec>      montty surface color --reset
          montty tab     color <spec>      montty tab     color --reset
          montty repo    color <spec>      montty repo    color --reset
          montty tab     name  <text>      montty tab     name  --reset
          montty surface status <working|waiting|idle|clear>
          montty hook <event>
          montty info
          montty --version

        <spec> is 1 to 3 comma-separated stops. A stop is a palette name
        (green, brightMagenta, neutralBright) or a six-digit hex value with
        or without a leading #.
        """

    static func parse(_ arguments: [String]) -> Result<ParsedInvocation, UsageError> {
        guard let first = arguments.first else { return .failure(.noArguments) }

        switch first {
        case "--version", "-v":
            return .success(.version)
        case "info":
            return .success(.control(.info))
        case "hook":
            guard arguments.count >= 2 else { return .failure(.missingValue("hook")) }
            return .success(.hook(arguments[1]))
        default:
            break
        }

        guard let scope = ControlScope(rawValue: first) else {
            return .failure(.unknownScope(first))
        }
        guard arguments.count >= 2 else { return .failure(.unknownProperty("")) }
        let property = arguments[1]
        let value = arguments.count >= 3 ? arguments[2] : nil

        switch (scope, property) {
        case (_, "color"):
            guard let value else { return .failure(.missingValue("color")) }
            if value == "--reset" { return .success(.control(.clearColor(scope: scope))) }
            return parseTint(value).map { .control(.setColor(scope: scope, tint: $0)) }

        case (.tab, "name"):
            guard let value else { return .failure(.missingValue("name")) }
            if value == "--reset" { return .success(.control(.clearName)) }
            return .success(.control(.setName(value)))

        case (.surface, "status"):
            guard let value else { return .failure(.missingValue("status")) }
            switch value {
            case "working": return .success(.control(.setStatus(.working)))
            case "waiting": return .success(.control(.setStatus(.waiting)))
            case "idle":    return .success(.control(.setStatus(.idle)))
            case "clear":   return .success(.control(.setStatus(nil)))
            default:        return .failure(.unknownStatus(value))
            }

        default:
            return .failure(.unknownProperty(property))
        }
    }

    private static func parseTint(_ spec: String) -> Result<PaneTint, UsageError> {
        let parts = spec.components(separatedBy: ",")
        guard parts.count <= PaneTint.maxStops else { return .failure(.tooManyStops) }

        var stops: [TintStop] = []
        for part in parts {
            guard let stop = TintStop.parse(part) else { return .failure(.badColor(part)) }
            stops.append(stop)
        }
        guard !stops.isEmpty else { return .failure(.badColor(spec)) }
        return .success(PaneTint(stops: stops))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `just check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: parse the montty CLI grammar

Color specs validate before anything reaches the socket, so a typo costs
a usage error and no round trip."
```

---

## Task 11: Teach the app binary to act as the CLI

**Superseded approach.** This task originally built a separate `montty-cli`
executable and copied it to `Contents/MacOS/montty`. That is impossible: macOS
ships a case-insensitive filesystem by default, so `Contents/MacOS/montty` and
the app's own `Contents/MacOS/Montty` are the same file. The copy silently
overwrites the app executable with the CLI and the build still reports success.
Verified directly: both paths report inode 250733403 on an APFS volume.

**What upstream does.** Ghostty ships exactly one binary.
`/Applications/Ghostty.app/Contents/MacOS/ghostty` is both the GUI app and the
CLI; `ghostty +version` prints and exits without initializing the app. Measured
dispatch cost is 10ms on a 41MB binary, the same as a `nc` round trip to the
control socket.

montty follows that. The app executable already resolves case-insensitively as
`montty` on PATH, so it only needs to dispatch on `CommandLine.arguments` before
`NSApplication.run()`. This removes the separate target, the `excludes` rule,
the bridging-header override, the copy phase, the nested-executable signing
question, the Homebrew `binary` stanza, and `just install-cli` — none of them
are needed.

**Files:**
- Modify: `Sources/App/main.swift` (dispatch on argv before creating the app)
- Create: `Sources/App/ControlCLI.swift` (the client: socket round trip, exit codes)
- Modify: `Sources/App/AppDelegate.swift` (inject `MONTTY_BIN`)
- Modify: `Sources/Control/ControlArgs.swift` (add `-v` to the usage string)

**Interfaces:**
- Consumes: `ControlArgs`, `ControlRequest`, `ControlResponse`.
- Produces: `ControlCLI.run(arguments:) -> Never`, called from `main.swift` when
  the first argument is not an app-launch argument; `MONTTY_BIN` in every
  surface's environment.

**Dispatch rule.** Treat the invocation as CLI when `CommandLine.arguments`
has more than one element and the first argument is not one macOS itself passes
(`-NSDocumentRevisionsDebugMode`, `-psn_*`, and anything else beginning with a
single `-` that is not `-v`). Everything else falls through to the GUI, so a
bare double-click and `open -a Montty` behave exactly as before.

**Distribution.** Nothing to install. GhosttyKit appends the running bundle's
`Contents/MacOS` to `PATH` for every shell it spawns
(`ghostty/src/termio/Exec.zig:684`), and the app executable answers to `montty`
there by case-insensitive match. `MONTTY_BIN` remains as the absolute-path
fallback for a shell that rewrote `PATH`.

Exit codes, grammar, and error text are unchanged from the original plan: 0 ok,
1 rejected, 2 not inside a montty pane, 3 montty not running, 64 usage error;
`montty hook` is fire-and-forget and always exits 0.


## Task 12: Fold the Claude Code hooks into the binary

**Files:**
- Modify: `project.yml` (the `claude()` wrapper heredoc at line 82)
- Modify: `docs/debug-server.md`
- Create: `docs/montty-cli.md`
- Test: manual, via the hook log

**Interfaces:**
- Consumes: `montty hook <event>` from Task 11.
- Produces: a wrapper with no `jq` or `nc` dependency.

- [ ] **Step 1: Rewrite the wrapper**

In `project.yml`, replace everything between `cat >> "${ZSH_ENV}" << 'MONTTY_HOOKS'` and the closing `MONTTY_HOOKS` with:

```sh
          # montty: wrap claude to inject hook callbacks for status tracking.
          # Six hooks map to state transitions:
          #   SessionStart/Stop           -> .idle
          #   UserPromptSubmit/PreToolUse -> .working
          #   Notification                -> .waiting
          #   SessionEnd                  -> entry removed
          # `montty hook` reads Claude's payload on stdin, forwards the cwd it
          # reports, and always exits 0 so a pane outside montty never makes
          # Claude Code look broken.
          #
          # MONTTY_BIN is the bundled binary's absolute path, injected into every
          # surface, so hooks keep working when the app was installed by dragging
          # it to /Applications and no Homebrew symlink exists. The PATH fallback
          # covers a pane whose environment predates that injection.
          if [[ -n "$MONTTY_SURFACE_ID" ]] \
             && { [[ -x "$MONTTY_BIN" ]] || command -v montty >/dev/null 2>&1; }; then
            claude() {
              local settings
              settings=$(cat <<'MONTTY_SETTINGS'
          {"hooks":{
            "SessionStart":     [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook session-start"}]}],
            "UserPromptSubmit": [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook prompt-submit"}]}],
            "PreToolUse":       [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook pre-tool-use"}]}],
            "Notification":     [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook notification"}]}],
            "Stop":             [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook stop"}]}],
            "SessionEnd":       [{"hooks":[{"type":"command","command":"\"${MONTTY_BIN:-montty}\" hook session-end"}]}]
          }}
          MONTTY_SETTINGS
              )
              command claude --settings "$settings" "$@"
            }
          fi
```

The guard changes from `command -v jq` to `-x "$MONTTY_BIN"`, because the binary is now the only dependency.

- [ ] **Step 2: Verify the hooks still drive the indicator**

```bash
just generate && just build && just run-bg
just inspect-type 'claude' && just inspect-key return
sleep 6
just inspect-hook-log | jq '.[-5:]'
```

Expected: `session-start` with `matched: true` and `newState: idle`.

```bash
just inspect-type 'say hello' && just inspect-key return
sleep 3
just inspect-hook-log | jq '.[-3:]'
```

Expected: `prompt-submit` with `newState: working`, and the pane's minimap indicator visibly active.

Confirm `jq` is genuinely no longer required by the wrapper:

```bash
grep -c 'jq' /tmp/montty-build/Debug/Montty.app/Contents/Resources/ghostty/shell-integration/zsh/.zshenv
```

Expected: `0`.

- [ ] **Step 3: Verify the generic status verb**

```bash
just inspect-type 'montty surface status waiting' && just inspect-key return
sleep 1
just inspect-surfaces | jq '.[] | select(.activity) | .activity'
```

Expected: a `waiting` state on the focused surface.

```bash
just inspect-type 'montty surface status clear' && just inspect-key return
sleep 1
just inspect-surfaces | jq '[.[] | select(.activity)] | length'
just stop
```

Expected: `0`.

- [ ] **Step 4: Document the CLI**

Create `docs/montty-cli.md`:

````markdown
# montty CLI

`montty` restyles the terminal surface and tab it runs in. It ships inside the
app bundle, and montty appends that bundle directory to `PATH` for every shell
it spawns, so `montty` resolves in any montty pane with no install step. Panes
also get `MONTTY_BIN` pointing at it by absolute path, for scripts that rewrite
`PATH`.

It only works from inside a montty pane. Run it anywhere else and it exits 2,
because there is no surface for it to act on.

## Commands

```
montty surface color <spec>          montty surface color --reset
montty tab     color <spec>          montty tab     color --reset
montty repo    color <spec>          montty repo    color --reset
montty tab     name  <text>          montty tab     name  --reset
montty surface status <working|waiting|idle|clear>
montty info
montty --version
```

`<spec>` is 1 to 3 comma-separated stops rendered as a left-to-right gradient.
A stop is a palette name resolved through your Ghostty theme (`green`,
`brightMagenta`, `neutralBright`; case and `-`/`_` are ignored) or a six-digit
hex value with or without a leading `#`.

## Scopes

Colors resolve surface first, then tab, then repo, then the automatic git
signature:

| scope | affects |
|---|---|
| `surface` | the one pane that ran the command |
| `tab` | every pane in the tab that has no surface override |
| `repo` | every tab whose focused pane sits in this repo or worktree |

Each scope has its own Reset in the tab's right-click menu, so anything set here
can be cleared from the GUI.

## Examples

```bash
montty tab name "MR !123 fix auth"
montty tab color neutralBright,green
montty surface color "#1a7f37"
montty info | jq -r .git.branch
```

## Exit codes

| exit | meaning |
|---|---|
| 0 | ok |
| 1 | montty rejected the request (unknown surface, not in a repo) |
| 2 | not running inside a montty pane |
| 3 | montty is not running |
| 64 | usage error: bad color spec, unknown scope or property |

## Activity status

`montty surface status` drives the same pane indicator Claude Code's hooks use,
so any long-running command can report progress:

```bash
just check && montty surface status idle || montty surface status waiting
```
````

Add a pointer to it from `ONBOARDING.md` under "Dig deeper":

```markdown
- [docs/montty-cli.md](./docs/montty-cli.md) -- the `montty` CLI for tab colors, names, and activity status
```

- [ ] **Step 5: Run the suite and commit**

Run: `just check`
Expected: PASS.

```bash
git add -A
git commit -m "feat: drive Claude Code hooks through the montty binary

The wrapper drops its jq and nc dependencies and collapses to a static
settings document, and montty surface status opens the same indicator to
any long-running command."
```

---

## Self-Review

**Spec coverage.** Every section of the spec maps to a task:

| spec section | task |
|---|---|
| Driving port (`ControlCommand`, `ControlService`, `SurfaceRef`, `ControlState`) | 6 |
| Source layout (`Sources/Control`, target lists) | 2, 11 |
| Color model (`TintStop`, `RGB`, hue derivation) | 2 |
| Scopes and precedence | 3, 4 |
| Socket location and `MONTTY_SOCKET` | 9 |
| Wire format and protocol versioning | 8 |
| The binary, `MONTTY_BIN`, inherited PATH append | 11 |
| CLI grammar and exit codes | 10, 11 |
| Claude fold-in and `montty surface status` | 12 |
| `ActivityStatus` rename | 1 |
| Context menu, three labeled scopes | 7 |
| Session v3, quarantine, backup, version gate | 5 |
| Error handling table | 10, 11 |
| Testing | every task |

**Type consistency.** `PaneTint.maxStops` is referenced in Tasks 3, 8, 10, and 11 and defined in Task 3. `ControlState`'s member list is defined in Task 6 and constructed identically in Tasks 6, 7, and the adapter in Task 7. `ControlArgs.parse` returns `Result<ParsedInvocation, UsageError>` in Task 10 and is consumed with that exact shape in Task 11. `ControlRequest.decode(_:)` throws `DecodeFailure` in Task 8 and is caught by those three cases in Task 9. `TintStop.parse`, `.text`, and `.hueFamily` are defined in Task 2 and used in Tasks 3, 8, and 10.

**Known ordering constraints.** Task 1 precedes Task 6 because `ControlCommand` names `ActivityStatus.State`. Task 3 must update `Sources/View/TabRow.swift` in the same commit as the `PaneTint` change, because `PaneTint+SwiftUI.swift` resolves `swiftUIColor` through the stop type. Task 4 must update every view signature in the same commit for the same reason. Tasks 2 through 5 land the type migration before any new user-visible behavior; Task 7 is the first task a user can see.
