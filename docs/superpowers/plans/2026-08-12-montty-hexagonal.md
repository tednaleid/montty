# montty Hexagonal Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move montty's window lifecycle and session decisions out of `AppDelegate` into effect-free functions that return values, so they can be tested without launching the app.

**Architecture:** A new `Sources/UseCase` layer holds `WindowUseCases`, which owns the `WindowRegistry`, mutates it directly, and returns a `WindowOutcome` value naming the AppKit work to do. `AppDelegate` becomes an imperative shell with one new job: interpret that value. There are no ports and no protocols, so the tests need no fakes.

**Tech Stack:** Swift 5, AppKit + SwiftUI, GhosttyKit, xcodegen, Swift Testing, SwiftLint, just.

**Spec:** `docs/superpowers/specs/2026-08-12-montty-hexagonal-design.md`

## Global Constraints

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Never XCTest.
- Tests verify observable runtime behavior, not source text or file contents.
- Full suite target: under 5 seconds. It currently passes at 364 tests in 36 suites.
- Every code file starts with two `// ABOUTME: ` lines.
- `Sources/UseCase` must not import `AppKit`, `Cocoa`, or `SwiftUI`. That constraint is what keeps it in the test target.
- `Sources/Model`, `Sources/Persistence`, and `Sources/Control` are unchanged by this plan except where a task says otherwise.
- `Sources/Ghostty` is not modified.
- `just test` does NOT run xcodegen. After creating any new file, run `just generate` before `just test` or the file is invisible to the build.
- `montty-unit` does not compile `Sources/App` or `Sources/View`. Nothing in those directories can be unit-tested.
- Ghostty's C API must be called on the main actor.
- Comments are evergreen: no dates, no ticket IDs, no "currently"/"for now", no narrating what was tried and rejected.
- No emojis, em-dashes, or hyperbole in documentation.
- `just check` (build + test + lint) must pass before every commit. The pre-commit hook runs it.

## Deviation from the spec, deliberate

The spec says the app-wide settings (`surfaceTintEnabled`, `repoColorOverrides`, `sidebarVisible`) move to a new `@Observable final class AppSettings` in `Sources/Model`. This plan does **not** do that.

Moving them means rewiring every SwiftUI view that reads `appDel.surfaceTintEnabled` through `@EnvironmentObject`, which is view-layer churn unrelated to the window lifecycle this slice is about. Instead the settings stay as `@Published` properties on `AppDelegate`, and cross the boundary as data: `restore` returns them in `WindowOutcome.applySettings` and the shell assigns them; `snapshot(...)` takes them as parameters.

The decision that actually broke — "a snapshot with zero windows still carries its settings" — is still a pure assertion on a returned value, which is the point. `AppSettings` can land in the view-layer slice where the rewiring belongs.

---

## File Structure

**Phase 1 — debug tooling**

- Modify `justfile` — add `inspect-shells`, `inspect-session`, `inspect-quit`.
- Modify `Sources/App/DebugServerHandlers.swift` — add `/session` and `/quit` routes and handlers.
- Modify `docs/debug-server.md` — document both endpoints and the three recipes.
- Modify `CLAUDE.md` — add the verification rule.

**Phase 2 — the extraction**

- Create `Sources/UseCase/WindowOutcome.swift` — the outcome value types. No logic.
- Create `Sources/UseCase/WindowUseCases.swift` — the decisions. Owns `WindowRegistry`.
- Create `Tests/WindowOutcomeTests.swift` — outcome value semantics.
- Create `Tests/WindowUseCasesTests.swift` — every decision.
- Modify `project.yml` — add `Sources/UseCase` to the `montty-unit` target.
- Modify `Sources/App/AppDelegate.swift` — hold `useCases`, forward `registry`, add `apply(_:)`.
- Modify `Sources/App/AppDelegate+WindowLifecycle.swift` — route the close paths through use cases.
- Modify `Sources/App/AppDelegate+Session.swift` — route restore and snapshot through use cases.
- Create `docs/architecture.md` — the living architecture description.
- Modify `CLAUDE.md`, `ONBOARDING.md` — point at it.

---

## Task 1: `just inspect-shells`

**Files:**
- Modify: `justfile` (add a recipe next to the other `inspect-*` recipes, after `inspect-windows` at line 169-170)

**Interfaces:**
- Consumes: nothing.
- Produces: a recipe named `inspect-shells`. No Swift code, no app change.

Every pane already carries `MONTTY_SURFACE_ID` in its environment, so the process table maps shells back to surfaces with no app change. Shells are NOT direct children of the montty process (they are reparented), so `pgrep -P` finds nothing — this is why previous leak checks planted sentinel `sleep` processes.

- [ ] **Step 1: Add the recipe**

Insert after the `inspect-windows` recipe:

```just
# Live shell PIDs, mapped to the surface each one runs in. A leak check is a
# set difference: capture this, close a window, confirm those pids are gone.
inspect-shells:
    @ps axeww 2>/dev/null | awk 'match($0, /MONTTY_SURFACE_ID=[0-9A-Fa-f-]+/) { \
        print "{\"pid\": " $1 ", \"surface\": \"" substr($0, RSTART+18, RLENGTH-18) "\"}" }' | jq -s .
```

`ps axeww` rather than `ps aeww`: the `x` includes processes with no controlling terminal, without which roughly half the shells are missed. The offset is 18, the length of `MONTTY_SURFACE_ID=`.

- [ ] **Step 2: Verify it against a running instance**

Launch a scratch instance. NEVER launch without both environment variables set, and keep the paths short — `sun_path` is capped at 103 bytes:

```bash
mkdir -p /tmp/mw
MONTTY_SESSION_DIR=/tmp/mw/s MONTTY_SOCKET=/tmp/mw/h.sock \
  /tmp/montty-build/Debug/Montty.app/Contents/MacOS/montty >/tmp/mw/log 2>&1 &
echo "started $!"
```

Wait a few seconds, then:

```bash
just inspect-shells
```

Expected: a JSON array with one entry per open pane, each with a numeric `pid` and a UUID `surface`. Cross-check the surface ids against `just inspect-surfaces | jq -r '.[].montty_surface_id'` — every id `inspect-shells` reports must appear there.

- [ ] **Step 3: Verify the leak-check use it exists for**

Record the shells, open a second window, close it, confirm its shells are gone:

```bash
just inspect-shells | jq -r '.[].pid' | sort > /tmp/mw/before
just inspect-action new_window
sleep 2
just inspect-shells | jq -r '.[].pid' | sort > /tmp/mw/after
comm -13 /tmp/mw/before /tmp/mw/after   # the new window's shell pid
```

Then close that window through the debug server and confirm the pid disappears from `just inspect-shells` and from `ps -p <pid>`.

- [ ] **Step 4: Stop the instance you started**

```bash
just stop
```

`just stop` is safe: it kills only Montty processes whose executable lives under the build directory, so it cannot reach an installed `/Applications/Montty.app`. Confirm nothing you started is left:

```bash
ps -eo pid=,comm= | grep -i montty
```

- [ ] **Step 5: Commit**

```bash
git add justfile
git commit -m "feat: add inspect-shells to map live shell pids to surfaces"
```

---

## Task 2: `GET /session`

**Files:**
- Modify: `Sources/App/DebugServerHandlers.swift` (add a route case near line 29 alongside `/palette`, and a handler)
- Modify: `justfile` (add `inspect-session`)
- Modify: `docs/debug-server.md`

**Interfaces:**
- Consumes: `AppDelegate.createSnapshot() -> SessionSnapshot`, which already exists.
- Produces: `GET /session` returning the live snapshot as JSON; recipe `inspect-session`.

Today the only way to see what montty would save is to quit it and read the file, which conflates "did we build the right snapshot" with "did we quit correctly".

- [ ] **Step 1: Add the route**

In `routeRequest`, alongside the other GET cases:

```swift
        case ("GET", "/session"):
            handleSession(connection: connection)
```

- [ ] **Step 2: Add the handler**

Add next to `handlePalette`. `createSnapshot()` touches `NSWindow` frames, so it must run on the main actor like the other handlers:

```swift
    /// The snapshot montty would write right now. Answers "what would we save"
    /// without quitting the app to find out.
    private static func handleSession(connection: NWConnection) {
        DispatchQueue.main.async {
            guard let appDelegate = AppDelegate.shared() else {
                sendJSON(["error": "no app delegate"], status: 500, connection: connection)
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(appDelegate.createSnapshot()),
                  let json = String(bytes: data, encoding: .utf8) else {
                sendJSON(["error": "could not encode snapshot"], status: 500, connection: connection)
                return
            }
            send(json, contentType: "application/json", connection: connection)
        }
    }
```

If no `send(_:contentType:connection:)` helper exists in `Sources/App/DebugServer.swift`, use the raw-body path the `/screenshot` handler uses for PNG bytes, adapted to `application/json`. Do not decode the snapshot into a dictionary and re-encode it — the point is to see exactly what `SessionStore` would write.

SwiftLint prefers `String(bytes:encoding:)` over `String(decoding:as:)`.

- [ ] **Step 3: Add the recipe**

```just
# The session snapshot montty would write right now
inspect-session:
    @curl -sf localhost:9876/session | jq .
```

- [ ] **Step 4: Verify against a running instance**

Launch a scratch instance as in Task 1, then:

```bash
just inspect-session | jq '{version, windows: (.windows | length), keyWindowID}'
just inspect-action new_window
sleep 2
just inspect-session | jq '.windows | length'
```

Expected: `version` is 4, the window count rises from 1 to 2 after `new_window`, and each window carries its own `frame` and `tabs`. Confirm the output matches the file the app actually writes:

```bash
diff <(just inspect-session | jq -S .) <(jq -S . /tmp/mw/s/session.json)
```

They may differ only by the autosave lag; re-run after a few seconds and they must converge. Stop the instance with `just stop`.

- [ ] **Step 5: Document it**

Add a `### GET /session` section to `docs/debug-server.md` between `/screen` and `/screenshot`, with the curl example and a note that it is the same value `SessionStore` writes. Add `just inspect-session` to the recipe table at the bottom.

- [ ] **Step 6: Commit**

```bash
just check
git add Sources/App/DebugServerHandlers.swift justfile docs/debug-server.md
git commit -m "feat: report the live session snapshot on /session"
```

---

## Task 3: `POST /quit` and the verification rule

**Files:**
- Modify: `Sources/App/DebugServerHandlers.swift`
- Modify: `justfile`
- Modify: `docs/debug-server.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `POST /quit`; recipe `inspect-quit`; a CLAUDE.md Rules entry.

The quit path is currently unreachable from a script. `just stop` sends SIGTERM, montty installs no SIGTERM handler, so `applicationShouldTerminate` never runs and the explicit pre-quit save is skipped — meaning `just stop` exercises a different path from Cmd-Q.

- [ ] **Step 1: Add the route and handler**

```swift
        case ("POST", "/quit"):
            handleQuit(connection: connection)
```

```swift
    /// Quits through the same path Cmd-Q takes, so a script can exercise the
    /// pre-quit save. SIGTERM does not: montty installs no handler for it, so
    /// applicationShouldTerminate never runs.
    private static func handleQuit(connection: NWConnection) {
        sendJSON(["ok": true], connection: connection)
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
```

The response is sent before terminating, since the process will not be alive to send it afterward.

- [ ] **Step 2: Add the recipe**

```just
# Quit the debug build through the real Cmd-Q path, saving the session
inspect-quit:
    @curl -sf -X POST localhost:9876/quit | jq .
```

- [ ] **Step 3: Verify the full quit-and-restore cycle**

This is the behavior no script could reach before. Launch a scratch instance, open a second window, quit through the endpoint, and confirm both windows were saved:

```bash
just inspect-action new_window
sleep 2
just inspect-session | jq '.windows | length'    # expect 2
just inspect-quit
sleep 2
jq '.windows | length' /tmp/mw/s/session.json    # expect 2
```

Then relaunch and confirm two windows come back:

```bash
MONTTY_SESSION_DIR=/tmp/mw/s MONTTY_SOCKET=/tmp/mw/h.sock \
  /tmp/montty-build/Debug/Montty.app/Contents/MacOS/montty >/tmp/mw/log2 2>&1 &
sleep 5
just inspect-windows
```

Expected: two windows. Stop with `just stop`.

- [ ] **Step 4: Add the CLAUDE.md verification rule**

In the `## Rules` section, directly after the "Tests should run fast" line:

```markdown
- Verify runtime app behavior through the debug HTTP server -- `just inspect-*` recipes and the
  `test-app` skill -- not by reasoning about it. See [docs/debug-server.md](./docs/debug-server.md).
```

This is the fix for a real failure: across roughly 45 subagent dispatches on the multi-window branch, none referenced the debug server or the `test-app` skill, and every agent that verified by execution hand-rolled raw `curl`. The tooling was named only in `ONBOARDING.md`, three hops away.

- [ ] **Step 5: Document the endpoint**

Add `### POST /quit` to `docs/debug-server.md`, stating plainly that it runs the same path as Cmd-Q and that `just stop`'s SIGTERM does not. Add `just inspect-quit` to the recipe table.

- [ ] **Step 6: Commit**

```bash
just check
git add Sources/App/DebugServerHandlers.swift justfile docs/debug-server.md CLAUDE.md
git commit -m "feat: quit through the real terminate path from the debug server"
```

---

## Task 4: The outcome value types

**Files:**
- Create: `Sources/UseCase/WindowOutcome.swift`
- Create: `Tests/WindowOutcomeTests.swift`
- Modify: `project.yml` (the `montty-unit` target's `sources` list, lines 122-126)

**Interfaces:**
- Consumes: `PaneTint` (from `Sources/Control`), `WindowFrame` (from `Sources/Model`). Both are in the same Xcode module, so no import is needed for either.
- Produces: `WindowOutcome`, `WindowPlan`, `SurfacePlan`, `SettingsUpdate`. Every later task returns and asserts on these.

- [ ] **Step 1: Add the directory to the test target**

In `project.yml`, under `montty-unit:` → `sources:`, add the new path:

```yaml
    sources:
      - path: Tests
      - path: Sources/Control
      - path: Sources/Model
      - path: Sources/Persistence
      - path: Sources/UseCase
```

The main `montty` target already builds all of `Sources`, so it needs no change.

- [ ] **Step 2: Write the failing test**

Create `Tests/WindowOutcomeTests.swift`:

```swift
// ABOUTME: Verifies the WindowOutcome value type defaults to doing nothing and
// ABOUTME: compares by value, which is what lets every use-case test assert on it.

import Testing

@Suite struct WindowOutcomeTests {
    /// A use case that decides nothing must return an outcome the shell can run
    /// safely, so every field defaults to inert.
    @Test func emptyOutcomeAsksForNothing() {
        let outcome = WindowOutcome()

        #expect(outcome.createWindows.isEmpty)
        #expect(outcome.createSurfaces.isEmpty)
        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.closeWindows.isEmpty)
        #expect(outcome.raiseWindow == nil)
        #expect(outcome.applySettings == nil)
        #expect(outcome.save == false)
        #expect(outcome.quit == false)
    }

    /// Every use-case test asserts by comparing outcomes, so equality must
    /// consider the fields rather than identity.
    @Test func outcomesCompareByValue() {
        let id = UUID()
        var first = WindowOutcome()
        first.destroySurfaces = [id]
        first.save = true

        var second = WindowOutcome()
        second.destroySurfaces = [id]
        second.save = true

        #expect(first == second)

        second.save = false
        #expect(first != second)
    }
}
```

- [ ] **Step 3: Run it and watch it fail**

```bash
just generate && just test
```

Expected: FAIL to build with "cannot find 'WindowOutcome' in scope". `just generate` is required — `just test` alone will not see the new files.

- [ ] **Step 4: Write the types**

Create `Sources/UseCase/WindowOutcome.swift`:

```swift
// ABOUTME: The value a window use case returns instead of performing effects --
// ABOUTME: the shell reads it and does the AppKit work it names.

import Foundation

/// What the shell must do as a result of one decision. Every field defaults to
/// inert, so a use case names only what it wants and the rest is a no-op.
struct WindowOutcome: Equatable {
    /// Windows whose models are already in the registry and now need an NSWindow.
    var createWindows: [WindowPlan] = []
    /// Surfaces to create; the shell reports the ids back via `surfacesCreated`.
    var createSurfaces: [SurfacePlan] = []
    var destroySurfaces: [UUID] = []
    /// Windows to close. Reaching the shell as `NSWindow.close()`, which comes
    /// back as `windowDidClose(id:)`.
    var closeWindows: [UUID] = []
    var raiseWindow: UUID?
    var applySettings: SettingsUpdate?
    var save = false
    var quit = false
}

struct WindowPlan: Equatable {
    let windowID: UUID
    /// A restored frame, or nil to let the shell place the window.
    let frame: WindowFrame?
    /// Offset from this window's on-screen frame. The shell computes the
    /// offset, since only it can read that frame.
    let cascadeFrom: UUID?
}

struct SurfacePlan: Equatable {
    /// The split-tree leaf this surface belongs to. The domain mints leaf ids;
    /// Ghostty mints surface ids, which is why binding them is a second step.
    let leafID: UUID
    let windowID: UUID
    let tabID: UUID
    let monttyID: String
    let workingDirectory: String?
}

/// App-wide settings a restore recovered. They live on the shell, so they cross
/// the boundary as data rather than being written directly.
struct SettingsUpdate: Equatable {
    let surfaceTintEnabled: Bool
    let repoColorOverrides: [String: PaneTint]
}
```

- [ ] **Step 5: Run the tests**

```bash
just check
```

Expected: PASS, 366 tests in 37 suites, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add project.yml Sources/UseCase/WindowOutcome.swift Tests/WindowOutcomeTests.swift
git commit -m "feat: add the window outcome value types"
```

---

## Task 5: `windowDidClose` — the decision that broke three times

**Files:**
- Create: `Sources/UseCase/WindowUseCases.swift`
- Create: `Tests/WindowUseCasesTests.swift`

**Interfaces:**
- Consumes: `WindowOutcome` (Task 4); `WindowRegistry`, `WindowModel`, `Tab`, `TabStore` from `Sources/Model`.
- Produces: `WindowUseCases(registry:)`, `.registry`, `.isTerminating`, `func windowDidClose(id: UUID) -> WindowOutcome`, `func applicationWillTerminate() -> WindowOutcome`.

`windowDidClose` is reached by all four teardown routes: the red button, the last tab closing, the `close_window`/`close_all_windows` actions, and quitting. Each was fixed separately on the previous branch and never reviewed together.

Useful existing API: `registry.windows` (`[WindowModel]`), `registry.window(id:) -> WindowModel?`, `registry.remove(id:)`, `registry.add(_:) -> WindowModel`, `window.tabStore.tabs`, and `tab.allSurfaceIDs` (`[UUID]`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/WindowUseCasesTests.swift`:

```swift
// ABOUTME: Verifies the window lifecycle decisions -- what to tear down, when to
// ABOUTME: save, and when to quit -- without launching the app.

import Foundation
import Testing

@Suite struct WindowUseCasesTests {
    /// A window holding `count` tabs, each with one surface, already registered.
    private func makeUseCases(windowSurfaceCounts: [Int]) -> (WindowUseCases, [WindowModel]) {
        let useCases = WindowUseCases(registry: WindowRegistry())
        var windows: [WindowModel] = []
        for count in windowSurfaceCounts {
            let window = useCases.registry.add(WindowModel())
            for position in 0..<count {
                let tab = Tab(position: position, surfaceID: UUID())
                window.tabStore.append(tab: tab)
            }
            windows.append(window)
        }
        return (useCases, windows)
    }

    @Test func closingTheLastWindowQuits() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.quit == true)
        #expect(useCases.registry.windows.isEmpty)
    }

    @Test func closingOneOfTwoWindowsSavesWithoutQuitting() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.quit == false)
        #expect(outcome.save == true)
        #expect(useCases.registry.windows.map(\.id) == [windows[1].id])
    }

    /// Surfaces that outlive their window leak a shell, so the outcome must name
    /// every one of them.
    @Test func closingAWindowNamesEverySurfaceItOwned() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [3, 1])
        let expected = windows[0].tabStore.tabs.flatMap(\.allSurfaceIDs)
        #expect(expected.count == 3)

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(Set(outcome.destroySurfaces) == Set(expected))
    }

    /// A quit already saved the complete pre-close state, so the per-window
    /// closes AppKit runs while terminating must not save a partial one over it.
    @Test func aCloseDuringTerminationDoesNotSave() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [2])
        _ = useCases.applicationWillTerminate()

        let outcome = useCases.windowDidClose(id: windows[0].id)

        #expect(outcome.save == false)
        #expect(outcome.quit == false)
    }

    @Test func terminatingSavesWhileWindowsRemain() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.applicationWillTerminate()

        #expect(outcome.save == true)
        #expect(useCases.isTerminating)
    }

    /// A quit that closed every window by hand has nothing left worth writing.
    @Test func terminatingWithNoWindowsDoesNotSave() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.applicationWillTerminate()

        #expect(outcome.save == false)
    }

    @Test func closingAnUnknownWindowDoesNothing() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])

        let outcome = useCases.windowDidClose(id: UUID())

        #expect(outcome == WindowOutcome())
        #expect(useCases.registry.windows.count == 1)
    }
}
```

- [ ] **Step 2: Run and watch them fail**

```bash
just generate && just test
```

Expected: FAIL to build with "cannot find 'WindowUseCases' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/UseCase/WindowUseCases.swift`:

```swift
// ABOUTME: Every window lifecycle and session decision, as functions that return
// ABOUTME: a WindowOutcome instead of touching AppKit, so they can be tested.

import Foundation

/// Owns the window registry and decides what should happen to it. Effect-free:
/// it mutates its own state and returns the AppKit work for the shell to run,
/// but performs no I/O and reaches no collaborator it was not constructed with.
final class WindowUseCases {
    let registry: WindowRegistry

    /// Latched once a quit is underway. `applicationShouldTerminate` saves the
    /// complete pre-close state, and AppKit then closes each window in turn --
    /// saving again on those would persist a mid-quit partial state over it.
    private(set) var isTerminating = false

    init(registry: WindowRegistry = WindowRegistry()) {
        self.registry = registry
    }

    /// AppKit is telling us a window closed. Closing a window is deliberate, so
    /// whatever remains afterward is what belongs on the next launch -- not what
    /// just closed.
    func windowDidClose(id: UUID) -> WindowOutcome {
        guard let window = registry.window(id: id) else { return WindowOutcome() }

        var outcome = WindowOutcome()
        outcome.destroySurfaces = window.tabStore.tabs.flatMap(\.allSurfaceIDs)
        registry.remove(id: id)

        guard !isTerminating else { return outcome }
        outcome.save = true
        outcome.quit = registry.windows.isEmpty
        return outcome
    }

    /// A quit is starting. Capture the full state before AppKit begins closing
    /// windows one at a time.
    func applicationWillTerminate() -> WindowOutcome {
        isTerminating = true
        var outcome = WindowOutcome()
        outcome.save = !registry.windows.isEmpty
        return outcome
    }
}
```

Note for the reviewer: the old code carried a second `lastQuitSnapshot` guard alongside `isTerminating`. The multi-window review confirmed it is unreachable in production and that it would suppress a legitimate empty write if it ever did fire. It is deliberately not carried over.

- [ ] **Step 4: Run the tests**

```bash
just check
```

Expected: PASS, 373 tests in 38 suites, 0 lint violations.

- [ ] **Step 5: Prove the tests fail against a broken decision**

A test that passes for the wrong reason is worse than no test, and this branch has shipped two. Verify each of these three mutations is caught, restoring the file after each:

1. Change `outcome.quit = registry.windows.isEmpty` to `outcome.quit = false` — `closingTheLastWindowQuits` must fail.
2. Delete the `guard !isTerminating else { return outcome }` line — `aCloseDuringTerminationDoesNotSave` must fail.
3. Change `window.tabStore.tabs.flatMap(\.allSurfaceIDs)` to `[]` — `closingAWindowNamesEverySurfaceItOwned` must fail.

Record the three failures in your report. If any mutation does NOT fail a test, the test is decorative — fix it before continuing.

- [ ] **Step 6: Commit**

```bash
git add Sources/UseCase/WindowUseCases.swift Tests/WindowUseCasesTests.swift
git commit -m "feat: decide window teardown, saving, and quitting as a value"
```

---

## Task 6: `newWindow`, `closeWindow`, and `surfacesCreated`

**Files:**
- Modify: `Sources/UseCase/WindowUseCases.swift`
- Modify: `Tests/WindowUseCasesTests.swift`

**Interfaces:**
- Consumes: everything from Task 5.
- Produces: `func newWindow(from surfaceID: UUID?) -> WindowOutcome`, `func closeWindow(containing surfaceID: UUID?) -> WindowOutcome`, `func surfacesCreated(_ bindings: [UUID: UUID]) -> WindowOutcome`.

`closeWindow(containing:)` is where the `close_window` defect lived: the observer discarded the surface it was handed and the key window closed instead. Requiring the parameter is what makes that hard to write.

Useful existing API: `registry.locate(surfaceID:) -> SurfaceLocation?` where `SurfaceLocation` has `.window`, `.tab`, `.surfaceID`; `registry.keyWindow -> WindowModel?`; `registry.keyWindowID`.

- [ ] **Step 1: Write the failing tests**

Append to `WindowUseCasesTests`:

```swift
    @Test func closingByASurfaceTargetsThatSurfacesWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        useCases.registry.keyWindowID = windows[1].id
        let surfaceInFirst = windows[0].tabStore.tabs[0].allSurfaceIDs[0]

        let outcome = useCases.closeWindow(containing: surfaceInFirst)

        #expect(outcome.closeWindows == [windows[0].id])
    }

    /// A caller that cannot resolve a surface falls back to the window in front.
    @Test func closingWithNoSurfaceTargetsTheKeyWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])
        useCases.registry.keyWindowID = windows[1].id

        let outcome = useCases.closeWindow(containing: nil)

        #expect(outcome.closeWindows == [windows[1].id])
    }

    /// The shell turns `closeWindows` into NSWindow.close(), which comes back as
    /// windowDidClose. Naming the same window in both would loop.
    @Test func closingDoesNotTearDownDirectly() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let outcome = useCases.closeWindow(containing: nil)

        #expect(outcome.destroySurfaces.isEmpty)
        #expect(outcome.save == false)
        #expect(useCases.registry.windows.count == 2)
        _ = windows
    }

    @Test func aNewWindowIsRegisteredAndAsksForOneSurface() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])
        useCases.registry.keyWindowID = windows[0].id

        let outcome = useCases.newWindow(from: nil)

        #expect(useCases.registry.windows.count == 2)
        #expect(outcome.createWindows.count == 1)
        #expect(outcome.createSurfaces.count == 1)

        let created = outcome.createWindows[0]
        #expect(created.cascadeFrom == windows[0].id)
        #expect(outcome.raiseWindow == created.windowID)
        #expect(outcome.createSurfaces[0].windowID == created.windowID)
    }

    /// A new window opens where you were, the rule createTab already applies.
    @Test func aNewWindowInheritsTheGivenSurfacesDirectory() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1])
        let surface = windows[0].tabStore.tabs[0].allSurfaceIDs[0]
        windows[0].tabStore.tabs[0].surfaceDirectories[surface] = "/Users/dev/work/alpha"

        let outcome = useCases.newWindow(from: surface)

        #expect(outcome.createSurfaces[0].workingDirectory == "/Users/dev/work/alpha")
    }

    /// Ghostty mints surface ids, so binding them to leaves is a second step.
    @Test func bindingSurfacesFillsInTheLeavesAndSaves() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [1])
        let outcome = useCases.newWindow(from: nil)
        let plan = outcome.createSurfaces[0]
        let surfaceID = UUID()

        let bound = useCases.surfacesCreated([plan.leafID: surfaceID])

        #expect(bound.save == true)
        let located = useCases.registry.locate(surfaceID: surfaceID)
        #expect(located?.window.id == plan.windowID)
        #expect(located?.tab.id == plan.tabID)
    }
```

- [ ] **Step 2: Run and watch them fail**

```bash
just test
```

Expected: FAIL to build with "value of type 'WindowUseCases' has no member 'newWindow'".

- [ ] **Step 3: Implement**

Add to `WindowUseCases`:

```swift
    /// Open a window with one tab, inheriting the working directory of the
    /// surface it was opened from. The model joins the registry now; the
    /// outcome describes only the AppKit work.
    func newWindow(from surfaceID: UUID?) -> WindowOutcome {
        let cascadeFrom = registry.keyWindow?.id
        let window = registry.add(WindowModel())
        let tab = Tab(position: 0)
        window.tabStore.append(tab: tab)
        window.tabStore.activeTabID = tab.id
        registry.keyWindowID = window.id

        // `Tab.init` seeds one leaf with a placeholder surface id. Take that
        // leaf's id: `surfacesCreated` remaps it to the id Ghostty mints.
        guard let leaf = SplitTree.allLeaves(node: tab.splitRoot).first else {
            return WindowOutcome()
        }

        var outcome = WindowOutcome()
        outcome.createWindows = [
            WindowPlan(windowID: window.id, frame: nil, cascadeFrom: cascadeFrom)
        ]
        outcome.createSurfaces = [
            SurfacePlan(
                leafID: leaf.id,
                windowID: window.id,
                tabID: tab.id,
                monttyID: UUID().uuidString,
                workingDirectory: surfaceID.flatMap(directory(ofSurface:))
            )
        ]
        outcome.raiseWindow = window.id
        return outcome
    }

    /// Close the window owning `surfaceID`. A caller that could not resolve one
    /// passes nil and the window in front closes. This only asks: the teardown
    /// happens when AppKit reports the close through `windowDidClose`.
    func closeWindow(containing surfaceID: UUID?) -> WindowOutcome {
        let target = surfaceID.flatMap { registry.locate(surfaceID: $0)?.window }
            ?? registry.keyWindow
        guard let target else { return WindowOutcome() }

        var outcome = WindowOutcome()
        outcome.closeWindows = [target.id]
        return outcome
    }

    /// Bind the surface ids Ghostty minted to the leaves that asked for them.
    func surfacesCreated(_ bindings: [UUID: UUID]) -> WindowOutcome {
        for window in registry.windows {
            for tab in window.tabStore.tabs {
                tab.bindSurfaces(bindings)
            }
        }
        var outcome = WindowOutcome()
        outcome.save = true
        return outcome
    }

    /// The working directory recorded for a surface, used so a new window opens
    /// where you were.
    private func directory(ofSurface surfaceID: UUID) -> String? {
        registry.locate(surfaceID: surfaceID)?.tab.surfaceDirectories[surfaceID]
    }
```

`Tab.bindSurfaces(_:)` does not exist yet. Add it to `Sources/Model/Tab.swift`, next to the other split-tree helpers:

```swift
    /// Point each leaf at the surface created for it. Leaves not named in
    /// `bindings` keep the surface they already have.
    func bindSurfaces(_ bindings: [UUID: UUID]) {
        splitRoot = SplitTree.mapLeaves(node: splitRoot) { leaf in
            guard let surfaceID = bindings[leaf.id] else { return leaf }
            surfaceToMonttyID[surfaceID] = surfaceToMonttyID[leaf.surfaceID]
            return SurfaceLeaf(id: leaf.id, surfaceID: surfaceID)
        }
    }
```

If `SplitTree.mapLeaves(node:_:)` does not exist, add it to `Sources/Model/SplitTree.swift` mirroring the shape of the existing `allLeaves(node:)` recursion, returning a rebuilt `SplitNode`. Cover it with its own test in `Tests/SplitTreeTests.swift` asserting a two-leaf branch has both leaves remapped and its orientation and ratio preserved.

- [ ] **Step 4: Run the tests**

```bash
just check
```

Expected: PASS with 0 lint violations.

- [ ] **Step 5: Prove the close targeting is real**

Change `closeWindow`'s first line to `let target = registry.keyWindow`, which is the exact defect this replaces. `closingByASurfaceTargetsThatSurfacesWindow` must fail. Restore it and record the failure in your report.

- [ ] **Step 6: Commit**

```bash
git add Sources/UseCase/WindowUseCases.swift Tests/WindowUseCasesTests.swift Sources/Model/Tab.swift Sources/Model/SplitTree.swift Tests/SplitTreeTests.swift
git commit -m "feat: decide new window, close window, and surface binding as values"
```

---

## Task 7: `restore` and `snapshot`

**Files:**
- Modify: `Sources/UseCase/WindowUseCases.swift`
- Modify: `Tests/WindowUseCasesTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 5 and 6.
- Produces: `func restore(_ snapshot: SessionSnapshot?) -> WindowOutcome`, `func snapshot(surfaceTintEnabled:repoColorOverrides:frames:directories:) -> SessionSnapshot`.

The cold-launch data-loss defect lived here: `restoreSession` assigned the app-wide settings below its early return, so a session with zero windows lost them and the autosave then wrote the defaults over the user's data.

- [ ] **Step 1: Write the failing tests**

```swift
    /// The defect this replaces: a file with no windows still carries its
    /// app-wide settings, and losing them destroys user data on the next save.
    @Test func restoringAFileWithNoWindowsStillRecoversSettings() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let saved = SessionSnapshot(
            surfaceTintEnabled: false,
            windows: [],
            keyWindowID: nil,
            repoColorOverrides: ["/Users/dev/work/alpha": PaneTint(stops: [.named(.blue)])]
        )

        let outcome = useCases.restore(saved)

        #expect(outcome.applySettings?.surfaceTintEnabled == false)
        #expect(outcome.applySettings?.repoColorOverrides.count == 1)
    }

    /// A quit that closed every window restores nothing, so the shell opens a
    /// fresh window the same way a first launch does.
    @Test func restoringAFileWithNoWindowsAsksForOneFreshWindow() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])

        let outcome = useCases.restore(SessionSnapshot(
            surfaceTintEnabled: true, windows: [],
            keyWindowID: nil, repoColorOverrides: [:]
        ))

        #expect(outcome.createWindows.count == 1)
        #expect(outcome.createSurfaces.count == 1)
    }

    @Test func restoringTwoWindowsRebuildsBothWithTheirDirectories() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let leafOne = UUID(), leafTwo = UUID()
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [
                windowSnapshot(leafID: leafOne, directory: "/Users/dev/work/alpha"),
                windowSnapshot(leafID: leafTwo, directory: "/Users/dev/work/beta")
            ],
            keyWindowID: nil,
            repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.windows.count == 2)
        #expect(outcome.createWindows.count == 2)
        #expect(Set(outcome.createSurfaces.map(\.workingDirectory)) ==
                ["/Users/dev/work/alpha", "/Users/dev/work/beta"])
    }

    /// A window whose tabs all vanished is not worth restoring.
    @Test func restoringSkipsWindowsWithNoTabs() {
        let (useCases, _) = makeUseCases(windowSurfaceCounts: [])
        let saved = SessionSnapshot(
            surfaceTintEnabled: true,
            windows: [
                WindowSnapshot(
                    windowID: UUID(), frame: WindowFrame(x: 0, y: 0, width: 800, height: 600),
                    sidebarWidth: 200, activeTabID: nil, tabs: []
                ),
                windowSnapshot(leafID: UUID(), directory: nil)
            ],
            keyWindowID: nil, repoColorOverrides: [:]
        )

        let outcome = useCases.restore(saved)

        #expect(useCases.registry.windows.count == 1)
        #expect(outcome.createWindows.count == 1)
    }

    @Test func aSnapshotCarriesEveryOpenWindow() {
        let (useCases, windows) = makeUseCases(windowSurfaceCounts: [1, 1])

        let snapshot = useCases.snapshot(
            surfaceTintEnabled: false,
            repoColorOverrides: [:],
            frames: [:],
            directories: [:]
        )

        #expect(snapshot.windows.count == 2)
        #expect(snapshot.surfaceTintEnabled == false)
        #expect(Set(snapshot.windows.map(\.windowID)) == Set(windows.map(\.id)))
    }

    /// A window snapshot with one tab holding one leaf at `leafID`.
    private func windowSnapshot(leafID: UUID, directory: String?) -> WindowSnapshot {
        let tab = TabSnapshot(
            tabID: UUID(), name: "", position: 0, focusedLeafID: leafID,
            splitLayout: .leaf(SurfaceLeaf(id: leafID, surfaceID: UUID())),
            leafDirectories: directory.map { [leafID: $0] } ?? [:],
            leafColorOverrides: [:], colorOverride: nil
        )
        return WindowSnapshot(
            windowID: UUID(),
            frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
            sidebarWidth: 200, activeTabID: tab.tabID, tabs: [tab]
        )
    }
```

Check the real initializer signatures of `SessionSnapshot`, `WindowSnapshot`, `TabSnapshot`, and `SurfaceLeaf` in `Sources/Persistence/SessionSnapshot.swift` and `Sources/Model/SplitTree.swift` before writing these, and match them exactly. Argument labels and ordering matter; adapt the calls above if they differ.

- [ ] **Step 2: Run and watch them fail**

```bash
just test
```

Expected: FAIL to build with "no member 'restore'".

- [ ] **Step 3: Implement**

```swift
    /// Rebuild the registry from a saved session. Windows join the registry
    /// now; the outcome names the AppKit work and the surfaces to create.
    func restore(_ snapshot: SessionSnapshot?) -> WindowOutcome {
        var outcome = WindowOutcome()
        if let snapshot {
            outcome.applySettings = SettingsUpdate(
                surfaceTintEnabled: snapshot.surfaceTintEnabled,
                repoColorOverrides: snapshot.repoColorOverrides
            )
        }

        let restorable = (snapshot?.windows ?? []).filter { !$0.tabs.isEmpty }
        guard !restorable.isEmpty else {
            var fresh = newWindow(from: nil)
            fresh.applySettings = outcome.applySettings
            return fresh
        }

        for saved in restorable {
            let window = registry.add(WindowModel(
                id: saved.windowID,
                sidebarWidth: saved.sidebarWidth,
                frame: saved.frame
            ))
            for savedTab in saved.tabs.sorted(by: { $0.position < $1.position }) {
                let tab = Tab(id: savedTab.tabID, name: savedTab.name, position: savedTab.position)
                tab.splitRoot = savedTab.splitLayout
                tab.focusedLeafID = savedTab.focusedLeafID
                tab.colorOverride = savedTab.colorOverride
                window.tabStore.append(tab: tab)

                for leaf in SplitTree.allLeaves(node: tab.splitRoot) {
                    outcome.createSurfaces.append(SurfacePlan(
                        leafID: leaf.id,
                        windowID: window.id,
                        tabID: tab.id,
                        monttyID: UUID().uuidString,
                        workingDirectory: savedTab.leafDirectories[leaf.id]
                    ))
                }
            }
            window.tabStore.activeTabID = saved.activeTabID ?? window.tabStore.tabs.first?.id
            outcome.createWindows.append(WindowPlan(
                windowID: window.id,
                frame: saved.frame.isEmpty ? nil : saved.frame,
                cascadeFrom: nil
            ))
        }

        let savedKey = snapshot?.keyWindowID
        registry.keyWindowID = savedKey.flatMap { registry.window(id: $0) != nil ? $0 : nil }
            ?? registry.windows.first?.id
        outcome.raiseWindow = registry.keyWindowID
        return outcome
    }

    /// The session montty would write right now. Takes the values only the
    /// shell can answer -- a window's on-screen frame and a surface's live
    /// working directory -- and the settings that live there.
    func snapshot(
        surfaceTintEnabled: Bool,
        repoColorOverrides: [String: PaneTint],
        frames: [UUID: WindowFrame],
        directories: [UUID: String]
    ) -> SessionSnapshot {
        SessionSnapshotBuilder.snapshot(
            windows: registry.windows,
            keyWindowID: registry.keyWindowID,
            surfaceTintEnabled: surfaceTintEnabled,
            repoColorOverrides: repoColorOverrides,
            environment: SessionEnvironment(
                frame: { frames[$0.id] ?? $0.frame },
                directory: { directories[$0] }
            )
        )
    }
```

Restore keeps the leaf ids from the saved layout and mints fresh surface ids through `surfacesCreated`, which is why `leafColorOverrides` is applied by the shell after binding rather than here.

- [ ] **Step 4: Run the tests**

```bash
just check
```

Expected: PASS with 0 lint violations.

- [ ] **Step 5: Prove the data-loss test is real**

Move the `outcome.applySettings = ...` assignment below the `guard !restorable.isEmpty` block, which recreates the original defect. `restoringAFileWithNoWindowsStillRecoversSettings` must fail. Restore and record it.

- [ ] **Step 6: Commit**

```bash
git add Sources/UseCase/WindowUseCases.swift Tests/WindowUseCasesTests.swift
git commit -m "feat: decide session restore and snapshot as values"
```

---

## Task 8: Route the close paths through the use cases

**Files:**
- Modify: `Sources/App/AppDelegate.swift`
- Modify: `Sources/App/AppDelegate+WindowLifecycle.swift`
- Modify: `Sources/App/AppDelegate+GhosttyActions.swift`

**Interfaces:**
- Consumes: `WindowUseCases` from Tasks 5-7.
- Produces: `AppDelegate.useCases`, `AppDelegate.apply(_ outcome: WindowOutcome)`. `AppDelegate.registry` keeps its current type and meaning, forwarding to `useCases.registry`, so `DebugServerHandlers`, `HookServer`, `ControlService`, and the views need no changes.

This is the integration task and carries the risk. Nothing here is unit-testable, so it is verified by running the app.

- [ ] **Step 1: Hold the use cases and forward the registry**

In `AppDelegate.swift`, replace the stored `let registry = WindowRegistry()` with:

```swift
    let useCases = WindowUseCases()
    /// The registry the use cases own. Every existing reader keeps working.
    var registry: WindowRegistry { useCases.registry }
```

Remove `var isTerminating` and `var lastQuitSnapshot` — `useCases.isTerminating` replaces the first and the second is deliberately dropped. Fix every reference the compiler reports.

- [ ] **Step 2: Add the shell**

In `AppDelegate+WindowLifecycle.swift`:

```swift
    /// Run the AppKit work an outcome names. The one place a decision becomes
    /// an effect.
    func apply(_ outcome: WindowOutcome) {
        if let settings = outcome.applySettings {
            surfaceTintEnabled = settings.surfaceTintEnabled
            repoColorOverrides = settings.repoColorOverrides
        }
        for plan in outcome.createWindows {
            makeWindow(plan)
        }
        if !outcome.createSurfaces.isEmpty {
            apply(useCases.surfacesCreated(createSurfaces(outcome.createSurfaces)))
        }
        for surfaceID in outcome.destroySurfaces {
            surfaceObservers.removeValue(forKey: surfaceID)
            surfaces.removeValue(forKey: surfaceID)
        }
        for id in outcome.closeWindows {
            let window = controllers[id]?.window
            DispatchQueue.main.async { window?.close() }
        }
        if let id = outcome.raiseWindow {
            controllers[id]?.window.makeKeyAndOrderFront(nil)
        }
        if outcome.save { saveSession() }
        if outcome.quit { NSApp.terminate(nil) }
    }
```

`createSurfaces(_:)` builds one `Ghostty.SurfaceView` per plan and returns `[leafID: surfaceID]`, reusing the config construction that `createTab` performs today (working directory plus the four `MONTTY_*` environment variables). `saveSession()` calls `sessionStore.save(snapshot: createSnapshot())`.

The recursion is bounded: `surfacesCreated` returns an outcome with only `save` set, so the nested `apply` cannot create more surfaces.

**`makeWindow` must no longer register the model.** Today it calls `registry.add(model)` and mints its own `WindowModel`. The use case has already done both by the time an outcome names the window, so adding again would double-register it. Its new shape takes a plan and looks the model up:

```swift
    @discardableResult
    func makeWindow(_ plan: WindowPlan) -> WindowController? {
        guard let model = registry.window(id: plan.windowID) else { return nil }
        let controller = WindowController(model: model, ghostty: ghostty, appDelegate: self)
        controllers[model.id] = controller
        if let source = plan.cascadeFrom, let from = controllers[source]?.window.frame {
            controller.window.setFrameTopLeftPoint(
                NSPoint(x: from.origin.x + 24, y: from.origin.y + from.height - 24)
            )
        }
        controller.show()
        return controller
    }
```

- [ ] **Step 3: Route the four teardown routes**

`windowWillClose(_ controller:)` becomes:

```swift
    func windowWillClose(_ controller: WindowController) {
        controller.window.contentView = nil
        apply(useCases.windowDidClose(id: controller.model.id))
        DispatchQueue.main.async { [weak self] in
            self?.controllers[controller.model.id] = nil
        }
    }
```

`applicationShouldTerminate` becomes:

```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let outcome = useCases.applicationWillTerminate()
        if outcome.save { saveSession() }
        return .terminateNow
    }
```

It must not call `apply` — `apply` would honor a `quit` field and re-enter `terminate`.

`newWindow()` becomes `apply(useCases.newWindow(from: focusedSurfaceID()))`, and `closeWindow()` becomes `apply(useCases.closeWindow(containing: surfaceID))`, taking the surface from the notification as the `close_window` observer in `AppDelegate+GhosttyActions.swift` already resolves it.

Keep the cascade: `makeWindow(_ plan:)` reads `controllers[plan.cascadeFrom]?.window.frame` and offsets the new window by 24 points, as `newWindow()` does today.

- [ ] **Step 4: Build and verify the four routes by running the app**

```bash
just check
```

Then launch a scratch instance (both environment variables, short paths, as in Task 1) and confirm each route. Use `just inspect-shells` to check shells are reaped and `just inspect-session` to check what would be saved:

1. **Red button** — open two windows, close one by hand. The closed window's shells disappear from `just inspect-shells`; the survivor's do not; `just inspect-session` lists one window.
2. **`close_window` action** — with two windows open and the second one key, `just inspect-action close_window <surface-in-first-window>`. The FIRST window must close.
3. **Last window** — close the remaining window. The process exits.
4. **Quit with two windows** — relaunch, open a second window, `just inspect-quit`, then confirm `jq '.windows | length' /tmp/mw/s/session.json` is 2 and a relaunch restores both.

Record all four results in your report, with the actual command output. Stop every instance you started with `just stop`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppDelegate.swift Sources/App/AppDelegate+WindowLifecycle.swift Sources/App/AppDelegate+GhosttyActions.swift
git commit -m "refactor: route window teardown through the use cases"
```

---

## Task 9: Route restore and snapshot through the use cases

**Files:**
- Modify: `Sources/App/AppDelegate+Session.swift`

**Interfaces:**
- Consumes: `useCases.restore(_:)`, `useCases.snapshot(...)`, `apply(_:)` from Task 8.
- Produces: `AppDelegate.createSnapshot()` keeps its signature, so `/session` from Task 2 and every other caller is unaffected.

- [ ] **Step 1: Replace `createSnapshot`**

```swift
    func createSnapshot() -> SessionSnapshot {
        var frames: [UUID: WindowFrame] = [:]
        for window in registry.windows {
            if let live = controllers[window.id]?.window.frame {
                frames[window.id] = WindowFrame(live)
            }
        }
        var directories: [UUID: String] = [:]
        for (surfaceID, view) in surfaces {
            if let pwd = view.pwd { directories[surfaceID] = pwd }
        }
        return useCases.snapshot(
            surfaceTintEnabled: surfaceTintEnabled,
            repoColorOverrides: repoColorOverrides,
            frames: frames,
            directories: directories
        )
    }
```

- [ ] **Step 2: Replace `restoreSession`**

```swift
    func restoreSession(_ snapshot: SessionSnapshot?) {
        apply(useCases.restore(snapshot))

        // Frames and focus settle after SwiftUI lays the hierarchy out. Each
        // surface calls becomeFirstResponder when it joins a window, so focus
        // needs the last word.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let visible = NSScreen.screens.map(\.visibleFrame)
            for window in self.registry.windows where !window.frame.isEmpty {
                self.controllers[window.id]?.window.setFrame(
                    window.frame.clamped(toVisible: visible).rect, display: true
                )
            }
            self.syncSurfaceFocus()
            self.focusActiveSurface()
        }
    }
```

Delete `restoreSplitNode` — `useCases.restore` plus `apply`'s surface creation replaces it. Apply each restored tab's `leafColorOverrides` in `createSurfaces(_:)` after binding, keyed by leaf id, so the colors land on the freshly minted surface ids.

Update the caller if its argument type changed: `restoreSession` now takes an optional and handles nil itself.

- [ ] **Step 3: Verify restore against real session files**

```bash
just check
```

Launch a scratch instance against a copy of a **real** v3 file — never point a montty at `~/Library/Application Support/montty/`, and never write to that directory:

```bash
mkdir -p /tmp/mw/s
cp ~/Library/Application\ Support/montty/session.json /tmp/mw/s/session.json
MONTTY_SESSION_DIR=/tmp/mw/s MONTTY_SOCKET=/tmp/mw/h.sock \
  /tmp/montty-build/Debug/Montty.app/Contents/MacOS/montty >/tmp/mw/log 2>&1 &
```

Confirm the tabs, splits, and working directories come back, that `just inspect-session` shows version 4 with the same tab count, and that the split layout matches. Then repeat the Task 8 step 4 quit-and-restore check to confirm two windows still round-trip. Record the output.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/AppDelegate+Session.swift
git commit -m "refactor: route session restore and snapshot through the use cases"
```

---

## Task 10: The architecture document

**Files:**
- Create: `docs/architecture.md`
- Modify: `CLAUDE.md`
- Modify: `ONBOARDING.md`

**Interfaces:**
- Consumes: the structure Tasks 4-9 built.
- Produces: documentation. No code.

- [ ] **Step 1: Write `docs/architecture.md`**

It must describe what is true when it lands, not the end state. Cover:

- The four directories and which the test target compiles: `Sources/Control`, `Sources/Model`, `Sources/Persistence`, `Sources/UseCase` are compiled by `montty-unit`; `Sources/App` and `Sources/View` are not.
- The rule: decisions live in `Sources/UseCase` and return `WindowOutcome` values; `Sources/App` translates events and runs effects and holds no decisions.
- Why there are no ports: the shell creates surfaces and loads the session, so nothing below the boundary calls outward and no test needs a fake.
- Two-phase surface creation, and why (the domain mints leaf ids, Ghostty mints surface ids).
- The `closeWindows` versus `windowDidClose` distinction, and the loop it prevents.
- **Explicitly**: window lifecycle and session have crossed the boundary. Tabs, splits, focus handling, and jump mode still live on `AppDelegate` and are scheduled for later slices. A reader must not be misled about a codebase that is mid-strangler.

Keep it under 120 lines. No emojis, no em-dashes, no hyperbole.

- [ ] **Step 2: Point at it from CLAUDE.md**

Add to the `## Rules` section:

```markdown
- Decisions live in `Sources/UseCase` as effect-free functions returning `Outcome` values;
  `Sources/App` translates events and runs effects, and holds no decisions. Read
  [docs/architecture.md](./docs/architecture.md) before adding logic to `Sources/App`.
```

The pointer is attached to the action that should trigger reading it, not filed under general orientation.

- [ ] **Step 3: Link it from ONBOARDING.md**

Add to the docs list, beside the `docs/debug-server.md` entry.

- [ ] **Step 4: Verify every claim**

Read the document against the code and confirm each statement. In particular confirm by grep that no decision remains in the window lifecycle files, and that the list of what has NOT crossed is accurate.

- [ ] **Step 5: Commit**

```bash
just check
git add docs/architecture.md CLAUDE.md ONBOARDING.md
git commit -m "docs: describe the use case and shell boundary"
```

---

## Safety constraints for every task

The human's own shell runs inside a live montty (`/Applications/Montty.app`, capital M). A previous agent destroyed one of their backup files here.

- NEVER launch a montty binary without setting BOTH `MONTTY_SESSION_DIR` and `MONTTY_SOCKET` to scratch paths under `/tmp/mw`. A montty on the defaults binds the live hook socket and autosaves over the real session file. `sun_path` is capped at 103 bytes, so keep the paths short.
- NEVER write to `~/Library/Application Support/montty/`. Copying out of it is fine.
- NO GUI scripting, AppleScript, or AXUIElement automation. AX resolves by process name and the installed app is also named `Montty`.
- `just stop` and `just kill` are safe: both act only on Montty processes whose executable lives under the build directory. Never `pkill` by name.
- `pgrep -f montty` is case-sensitive and misses the installed capital-M `Montty`. Use `ps -eo pid=,comm= | grep -i montty` to confirm cleanup.
- Before finishing a task, confirm no instance you started is still running and the working tree is clean.
