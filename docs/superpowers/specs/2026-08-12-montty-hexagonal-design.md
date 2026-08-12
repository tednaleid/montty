# montty hexagonal pivot design

Visual companion, with before/after diagrams: `.llm/hexagonal-design.html` (gitignored;
regenerate by opening it, or re-render figures with the scratchpad screenshot harness).

## Goal

Move montty's window lifecycle and session decisions out of `AppDelegate` and into pure
functions that return values, so the decisions can be tested without launching the app.

## Why

The multi-window branch produced roughly sixteen defects. Sorted by kind, exactly one was a
logic error inside a pure function. About eight were composition errors: correct pieces wired
together wrong. An observer that discarded the surface it was handed. A screenshot that raised
one window and captured another. Two assignments below a guard instead of above it.

Every one of those lives in `Sources/App`, which no test target compiles. All 925 lines of new
tests went to `Sources/Model`, the layer holding the single logic defect. The tests were sound
and aimed at the part that was not breaking.

`montty-unit` compiles `Tests`, `Sources/Control` (962 lines), `Sources/Model` (1,828), and
`Sources/Persistence` (298). It does not compile `Sources/App` (3,045) or `Sources/View` (895).

## Non-goals

Tabs, splits, focus handling, and jump mode stay on `AppDelegate` in this work. They convert in
later slices. Converting everything at once would reproduce the review problem this pivot is
meant to fix, where nothing can be judged until everything is done.

No new dependencies, no mocking framework, no DI container. The design's whole point is that it
needs none.

`Sources/Ghostty` is not modified.

## Phase 1: make the app-level residue cheap to check

Four items survive this pivot that only a running app can catch: object lifetime
(`isReleasedWhenClosed` double-release), the content-view leak, AppKit closing windows
individually during `terminate()`, and first-responder timing. They concern AppKit's contract
rather than montty's features, so the set is small and does not grow as features are added.

Phase 1 buys a fast way to check them by hand, not a permanent automated suite. A launch-the-app
suite costs about 5 seconds per test, is timing-sensitive, and probably cannot gate CI, since a
macOS GUI app on a runner has no window server. That makes a large suite a liability.

### `just inspect-shells`

Every pane already carries `MONTTY_SURFACE_ID` in its environment, so the process table maps
back to surfaces with no app change:

```
ps axeww | awk 'match($0, /MONTTY_SURFACE_ID=[0-9A-Fa-f-]+/) {
  print "pid=" $1 "  surface=" substr($0, RSTART+18, RLENGTH-18) }'
```

Verified at 68ms against a live montty. Shells are not direct children of the montty process
(they are reparented), which is why `pgrep -P` does not find them and why every previous leak
check planted a sentinel `sleep`. This retires that pattern: capture the pids for a window's
surfaces, close the window, assert the set is gone.

### `GET /session` and `just inspect-session`

Returns the live `createSnapshot()` as JSON. Today the only way to see what montty would save is
to quit it and read the file, which conflates "did we build the right snapshot" with "did we
quit correctly". Both the cold-launch data-loss defect and the only-the-key-window snapshot
defect are one assertion against this endpoint.

`createSnapshot()` already delegates to `SessionSnapshotBuilder` in `Sources/Model`, so the
handler is a serialization of an existing pure value.

### `POST /quit` and `just inspect-quit`

Calls `NSApp.terminate(nil)` on the main actor. `DEBUG` only, like every other debug endpoint.

The quit path is currently unreachable from a script: `just stop` sends SIGTERM, the app
installs no SIGTERM handler, so `applicationShouldTerminate` never runs and the explicit
pre-quit save is skipped. `just stop` therefore exercises a different path from Cmd-Q. With
`/quit` and `/session` together, the quit-and-restore cycle becomes scriptable for the first
time.

### CLAUDE.md discoverability

The debug server is currently named only in `ONBOARDING.md`, as two entries in a file list, three
hops from `CLAUDE.md`. Across roughly 45 subagent dispatches on the multi-window branch, not one
referenced it or the `.claude/skills/test-app` skill, and every agent that verified by execution
hand-rolled raw `curl`. The instruction to prefer `just inspect-*` existed only in the
controlling session's memory, which subagents do not inherit.

Add to the Rules section of `CLAUDE.md`, at the same level as the Swift Testing rule:

```markdown
- Verify runtime app behavior through the debug HTTP server -- `just inspect-*` recipes and the
  `test-app` skill -- not by reasoning about it. See [docs/debug-server.md](./docs/debug-server.md).
```

The rule is placed where it is read before the work, not discovered after.

### Phase 1 testing

These are debug-only endpoints and a shell recipe. There is no meaningful unit test for them, and
inventing one would be theatre. They are verified by running them against a scratch instance
(`MONTTY_SESSION_DIR` and `MONTTY_SOCKET` under a short path) and confirming output. That
verification is recorded in the task's report, not committed as a test.

## Phase 2: window lifecycle and session

Window lifecycle and session convert together. They are entangled: restore *creates* windows, and
the cold-launch data-loss defect lived exactly at that seam. Splitting them would leave restore
constructing `NSWindow`s directly.

### Where the code lives

New directory `Sources/UseCase`, added to the `montty-unit` target's `sources` list in
`project.yml` alongside `Sources/Control`, `Sources/Model`, and `Sources/Persistence`.

It imports `Foundation` only. It must not import `AppKit`, `Cocoa`, or `SwiftUI` -- that
constraint is what puts it in the test target, and `Sources/Model`, `Persistence`, and `Control`
already hold it today.

`Sources/Model` does not change.

### The pattern: effect-free functions returning Outcome values

A use case takes an event, updates its own in-memory domain state, and returns a value naming
the effects to run. It performs none of them.

"Effect-free" is the precise claim, not "pure": a use case owns and mutates `registry`,
`settings`, and `isTerminating`, so calling one twice is not the same as calling it once. What it
never does is perform I/O, touch AppKit, or reach any collaborator it was not constructed with.
That is what makes it testable, and it is why there are no ports, no protocols, and no injected
collaborators -- so tests need no fakes of any kind.

```swift
struct WindowOutcome: Equatable {
    var createWindows: [WindowPlan] = []
    var createSurfaces: [SurfacePlan] = []
    var destroySurfaces: [UUID] = []
    var closeWindows: [UUID] = []
    var raiseWindow: UUID?
    var save: Bool = false
    var quit: Bool = false
}

struct WindowPlan: Equatable {
    let windowID: UUID
    let frame: WindowFrame?     // a restored frame, or nil to let the shell place it
    let cascadeFrom: UUID?      // offset from this window's frame, nil for no cascade
}

struct SurfacePlan: Equatable {
    let leafID: UUID
    let monttyID: String
    let workingDirectory: String?
}
```

`save` is a `Bool` rather than a `SessionSnapshot`. The decision worth testing is *whether* to
save; building the snapshot is already covered by `SessionSnapshotBuilder`. Keeping it a flag
means the decision needs no window frames or working directories threaded into it.

### The use cases

```swift
final class WindowUseCases {
    let registry: WindowRegistry
    let settings: AppSettings
    private(set) var isTerminating = false

    init(registry: WindowRegistry, settings: AppSettings)

    func newWindow(from surfaceID: UUID?) -> WindowOutcome
    func closeWindow(containing surfaceID: UUID?) -> WindowOutcome
    func windowDidClose(id: UUID) -> WindowOutcome
    func restore(_ snapshot: SessionSnapshot?) -> WindowOutcome
    func surfacesCreated(_ bindings: [UUID: UUID]) -> WindowOutcome
    func applicationWillTerminate() -> WindowOutcome

    func snapshot(
        frames: [UUID: WindowFrame],
        directories: [UUID: String]
    ) -> SessionSnapshot
}
```

`snapshot(frames:directories:)` takes the two values only AppKit can supply, matching the
`SessionEnvironment` closure pair `SessionSnapshotBuilder` already uses. The shell reads a
window's real frame from its `NSWindow` and a surface's working directory from its
`SurfaceView`, exactly as `AppDelegate.createSnapshot()` does today.

**Domain state updates immediately; the Outcome describes only the AppKit work.** `newWindow`
and `restore` add their `WindowModel`s to `registry` before returning, so the registry is correct
the moment the call comes back. `createWindows` then tells the shell which `NSWindow`s to build
for models that already exist. The same holds in reverse for `windowDidClose`, which removes from
the registry and reports the surfaces to tear down. An implementer must not read `createWindows`
as "the registry will be updated later".

`WindowPlan.cascadeFrom` names the window to offset from; the shell computes the offset, since
only it can read the source window's on-screen frame.

`closeWindow(containing:)` takes the surface that asked. A caller that cannot resolve one passes
`nil` and the key window closes. Requiring the parameter is what makes the `close_window` defect
hard to write: the adapter must supply something, and the notification's object is the only
thing it has.

### Two-phase surface creation

Ghostty mints surface ids; the domain mints leaf ids. `restoreSplitNode` already straddles that
split today. This design makes it explicit:

1. A use case returns an Outcome whose `createSurfaces` names each leaf id, its montty surface
   id, and its working directory.
2. The shell creates a Ghostty surface per entry and collects `[leafID: surfaceID]`.
3. The shell calls `surfacesCreated(_:)`, which binds them into the split tree and returns a
   further Outcome (typically `save: true`, and `raiseWindow` on a fresh window).

This is more ceremony than calling a `SurfaceHost` port and getting an id back. It is the price
of every use case being a pure function, which is what removes the need for test doubles.

### Re-entrancy: `closeWindows` versus `windowDidClose`

Two distinct things share one word today, and conflating them is where three defects came from.

- `closeWindows: [UUID]` in an Outcome means *I want this window closed*. The shell calls
  `NSWindow.close()`.
- `windowDidClose(id:)` means *AppKit is telling us a window closed*. It is a driving event,
  reached by all four routes: the red button, the last tab closing, the `close_window` and
  `close_all_windows` actions, and quitting.

`windowDidClose(id:)` must never return that same id in `closeWindows`, or the shell loops. The
shell defers `NSWindow.close()` by one run loop turn, as it does today, because the call can
originate from a Ghostty action on a surface inside the window being closed.

### What stays in `Sources/App`

`AppDelegate` keeps the Ghostty app handle, the `surfaces` and `controllers` dictionaries, the
timers, the servers, and the observers. It gains one job: interpret a `WindowOutcome`.

```swift
func apply(_ outcome: WindowOutcome) {
    for plan in outcome.createWindows { /* NSWindow + WindowController */ }
    for plan in outcome.createSurfaces { /* Ghostty.SurfaceView */ }
    for id in outcome.destroySurfaces { /* drop from surfaces, surfaceObservers */ }
    for id in outcome.closeWindows { /* deferred NSWindow.close() */ }
    if let id = outcome.raiseWindow { /* makeKeyAndOrderFront */ }
    if outcome.save { sessionStore.save(snapshot: useCases.snapshot(...)) }
    if outcome.quit { NSApp.terminate(nil) }
}
```

`tabPalette` stays on `AppDelegate`. It is `[NSColor]` read only by `TabRow` rendering and the
`/palette` endpoint; the domain speaks in `PaneTint` palette names, so it never crosses the
boundary.

### The stranded app-wide settings

`AppDelegate` holds five `@Published` properties. `surfaceTintEnabled`, `repoColorOverrides`, and
`sidebarVisible` are domain state and move to a new `@Observable final class AppSettings` in
`Sources/Model`, which views bind to directly the way they already bind to `TabStore`.
`jumpState` stays until the jump-mode slice. `tabPalette` stays permanently, as above.

### Architecture document

`docs/architecture.md`, committed, written as part of this phase and describing what is true when
it lands -- not the end state. It states which subsystems have crossed the boundary (window
lifecycle, session) and which still live on `AppDelegate` (tabs, splits, focus, jump mode), so a
reader is not misled about a codebase that is mid-strangler.

`CLAUDE.md` gains a Rules entry pointing at it, attached to the moment it matters:

```markdown
- Decisions live in `Sources/UseCase` as pure functions returning `Outcome` values;
  `Sources/App` translates events and runs effects, and holds no decisions. Read
  [docs/architecture.md](./docs/architecture.md) before adding logic to `Sources/App`.
```

`ONBOARDING.md` links it from the docs list as well.

## Testing

Every use case is tested by constructing a `WindowUseCases` over a fresh `WindowRegistry`,
calling one method, and asserting on the returned struct. No app, no window, no fakes,
sub-millisecond. The full suite stays under the 5 second target.

The cases that must exist, each of which corresponds to a defect this branch actually shipped:

- `windowDidClose` on the last window returns `quit: true`; on a non-last window returns
  `quit: false` and `save: true`.
- `windowDidClose` returns every surface id in the closed window under `destroySurfaces`.
- `windowDidClose` while `isTerminating` returns `save: false`.
- `closeWindow(containing:)` targets the window owning that surface, not the key window, when
  they differ.
- `restore` of a snapshot with zero windows still applies `surfaceTintEnabled` and
  `repoColorOverrides` to settings.
- `restore` of a snapshot with two windows returns two `createWindows` and the right
  `createSurfaces` per leaf, with working directories preserved.
- `surfacesCreated` binds leaf ids to surface ids so the resulting split tree matches the
  snapshot's shape.
- `applicationWillTerminate` returns `save: true` while windows remain, and latches
  `isTerminating`.

Existing `Sources/Model` tests are unaffected. The suite must still pass at its current count plus
the new cases, with zero SwiftLint violations.

## Risks

The codebase holds two idioms at once until the later slices land: converted window and session
paths, and unconverted tab, split, and focus paths still on `AppDelegate`. The architecture
document exists specifically so that is documented rather than confusing.

Two-phase surface creation is the part most likely to feel worse in practice than on paper. If
it proves painful in this slice, reconsider before converting tabs and splits -- reintroducing a
single `SurfaceHost` port is a small change, and this slice is where we learn whether it is
needed.

`windowDidClose` is reached by four routes that were each fixed separately on the previous
branch and never reviewed together. Converting them to one entry point is the main value of this
slice and also its main risk. The Phase 1 tooling exists to check the result against a running
app before merging.

## Deferred

Tabs, splits, focus handling, and jump mode. Each is its own slice, and each should be a separate
branch reviewable on its own.
