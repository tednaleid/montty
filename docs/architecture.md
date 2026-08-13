# Architecture

montty is moving decisions out of `AppDelegate` and into a layer that can be
tested without AppKit. This describes the shape as it stands, not the end
state.

## Directories and the test boundary

`project.yml` compiles two targets from the same source tree:

- `montty` (the app) compiles all of `Sources`.
- `montty-unit` (the test target) compiles only `Sources/Control`,
  `Sources/Model`, `Sources/Persistence`, and `Sources/UseCase`. It does not
  compile `Sources/App` or `Sources/View`.

That membership is the boundary. Anything that needs to be unit-tested has to
live in one of the four compiled directories: `montty-unit` never compiles a
single file from `Sources/App` or `Sources/View`, so nothing that lives
there is visible to a test at all.

## The rule

Decisions live in `Sources/UseCase` as functions that mutate the model and
return an `Outcome` value describing what the shell should do -- they never
touch AppKit. `Sources/App` translates AppKit events into calls on a use
case, then reads the outcome it gets back and runs the effects it names:
building an `NSWindow`, creating a Ghostty surface, writing the session file,
calling `NSApp.terminate(nil)`.

`WindowUseCases` (`Sources/UseCase/WindowUseCases.swift`) is the use case for
window lifecycle and session. Each method takes the shell's request, updates
the `WindowRegistry` it owns, and returns a `WindowOutcome`
(`Sources/UseCase/WindowOutcome.swift`) -- a struct of arrays and optionals,
every field defaulting to inert, naming only the AppKit work that decision
requires. `AppDelegate.apply(_:)`
(`Sources/App/AppDelegate+WindowLifecycle.swift`) is the one place that reads
a `WindowOutcome` and runs it.

This holds today for window lifecycle and session. `newWindow`, `closeWindow`,
`windowDidClose`, `surfacesCreated`, and `restore` return a `WindowOutcome`
that `apply(_:)` interprets. `applicationShouldTerminate` also returns a
`WindowOutcome`, but its `save` field is read directly rather than passed to
`apply(_:)`, to avoid re-entering `NSApp.terminate`. `snapshot` returns a
`SessionSnapshot` value, not an outcome, and is written to disk directly. It
does not yet hold for tabs, splits, focus handling, or jump mode -- see below.

## Why there are no ports

A hexagonal boundary usually needs ports: interfaces the inner layer defines
and the outer layer implements, so the inner layer can call out (to a
database, a clock, a network) without depending on the concrete adapter.
`Sources/UseCase` has none. `WindowUseCases` and `WindowOutcome` import only
`Foundation` and define no protocols. The traffic is one-directional: the
shell calls into a use case and reads back a value. Nothing below the
boundary calls outward, because the two things an outer layer would
otherwise be asked for -- creating a Ghostty surface, and loading the saved
session -- both originate on the shell side already. `AppDelegate` creates
surfaces and owns the `SessionStore`; the use case only describes what to
create or asks to be handed a snapshot to restore from. No test needs a
fake, because there is nothing to fake.

## Two-phase surface creation

A use case cannot create a Ghostty surface -- only `Sources/App` can call
into `GhosttyKit`. So creating one is split in two. `WindowUseCases` mints a
split-tree leaf id and returns it in a `SurfacePlan`
(`Sources/UseCase/WindowOutcome.swift`), asking the shell to create a
surface for that leaf. `AppDelegate.createAndBindSurfaces`
(`Sources/App/AppDelegate+WindowLifecycle.swift`) creates the Ghostty
surface, which mints its own surface id, and reports the leaf-id-to-surface-
id mapping back through `surfacesCreated(_:)`, which binds each leaf to the
id Ghostty gave it. The domain owns leaf identity because it has to exist
before any surface does -- a restored split layout is leaves before it is
surfaces -- and Ghostty owns surface identity because only Ghostty can mint
one.

## `closeWindows` versus `windowDidClose`

`closeWindow(containing:)` only asks: it returns a `closeWindows` list in
the outcome, and `apply(_:)` runs `NSWindow.close()` on each one. It does
not touch the registry. The actual teardown -- dropping the window from the
registry, deciding whether to save, deciding whether this was the last
window and the app should quit -- happens in `windowDidClose(id:)`, called
from `AppDelegate.windowWillClose(_:)` once AppKit reports the window is
actually gone.

Collapsing these into one step would double the decision: closing a window
eagerly through the registry and then again when AppKit's own close
notification arrived a moment later. Keeping them separate means a close
request is only ever a request, and the registry changes exactly once per
window, on the callback that confirms the window is gone -- whether that
close was asked for by `closeWindow`, by the window's own red button, or by
`closeAllWindows` closing every window in turn.

## What has crossed, and what has not

Window lifecycle and session have crossed the boundary. Tabs, splits, focus
handling, and jump mode have not -- they still hold their decisions on
`AppDelegate` directly:

- tabs -- `createTab(in:)` and `closeTab(id:)`
- splits -- `closeSurface(surfaceID:)` and `splitSurface(direction:in:)`
- focus handling -- `focusedSurfaceID()` and `focusActiveSurface()`
- jump mode

These are untested by `montty-unit` today, for the same reason nothing in
`Sources/App` is: the test target's source list does not include that
directory. Moving them across the boundary is later work, not implied by
anything here.
