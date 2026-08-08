# montty control CLI

A `montty` binary that lets a shell, a script, or an agent restyle the terminal
surface and tab it is running in.

## Motivation

Montty derives tab colors from git repo identity and tab names from the terminal
title. Both are good defaults and neither can be driven from inside the
terminal. A code review workflow wants every review pane to carry the same
signature color and the merge request title, set by the tool that opened it.
Skills and agents want the same thing without a human right-clicking a tab.

Three actors want to make the same mutations today, by three different paths:
the right-click menu writes `AppDelegate` fields through closures wired in
`MainWindow.swift`, the Claude Code hook wrapper calls `HookStateMachine.apply`
from `HookServer`, and the CLI would be a third. Adding the third without a
shared write path means the precedence and validation rules live in three places
and drift.

## Goals

- Set surface, tab, and repo colors from the command line, including hex and
  multi-stop gradients.
- Set the tab name from the command line.
- Drive the pane activity indicator from any process, not only Claude Code.
- Read back the calling surface's identity and effective styling as JSON.
- Give the three driving actors one write path into the model.

## Non-goals

- Cross-surface or cross-tab targeting. Every command affects the surface it
  runs in. No `--tab` or `--surface` flags, no `montty list`.
- Remote reach. The transport is a unix socket, so SSH sessions, containers, and
  remote tmux servers cannot reach montty. OSC escape sequences would work there
  but require custom parsing in Ghostty's Zig source, which forks upstream and
  fights `just sync-bindings`.
- Per-surface names. `SplitMinimap` carries only activity status per pane, with
  nowhere to render a label.
- Driven ports. Persistence and git each have one implementation; protocols
  there would be ceremony without inversion.
- Arbitrary badge glyphs. Activity status stays a fixed set of states.
- `MONTTY_PORT` stays as it is, still pointing at the debug HTTP port that only
  exists in Debug builds. Misleading, but out of scope here.

## Architecture

### The driving port

`ControlCommand` is the port: the complete set of mutations an outside actor can
request. `ControlService.apply` is the application core that enforces
precedence and validation. Both are pure and Foundation-only.

```swift
enum ControlScope { case surface, tab, repo }

enum ControlCommand {
    case setColor(scope: ControlScope, tint: PaneTint)
    case clearColor(scope: ControlScope)
    case setName(String)
    case clearName
    case setStatus(ActivityStatus.State?)   // nil clears
    case info
}

enum ControlResult {
    case applied
    case read(ControlInfo)              // the `.info` payload
    case rejected(ControlError)         // unknownSurface, notInRepo, …
}

enum ControlService {
    static func apply(
        _ command: ControlCommand,
        target: SurfaceRef,
        to state: inout ControlState,
        gitInfoProvider: (String) -> GitInfo? = GitInfo.from(path:)
    ) -> ControlResult
}
```

`ControlState` is a narrow struct over exactly what is mutable — tab name, the
three override collections, and activity states — not the whole `Tab` or
`AppDelegate`.

`SurfaceRef` resolves a `MONTTY_SURFACE_ID` to the surface, leaf, and tab that
own it, plus that surface's effective directory (Claude's reported cwd when
present, otherwise the shell pwd). Building it is the adapter's job, so
`ControlService` never walks the tab store.

`.info` is a read and leaves `state` untouched; it lives in the same enum so the
adapters have one entry point rather than two. `ControlResult.read` carries the
payload.

Only `.setColor` and `.clearColor` take a scope. Names are tab-level and status
is surface-level, so those cases carry no scope — the CLI grammar reflects that
with `montty tab name` and `montty surface status`.

`gitInfoProvider` is the single driven dependency, needed to resolve repo
identity for `scope: .repo`. It uses the injected-function seam already
established by `TabInfo.from` (`Sources/Model/TabInfo.swift:13`) rather than
introducing a protocol.

Three adapters funnel through `apply`:

| adapter | path |
|---|---|
| `montty` CLI | argv → `ControlRequest` JSON → socket → decode → `apply` |
| right-click menu | menu action → `ControlCommand` → `apply` |
| Claude hooks | `ClaudeHookEvent` → `.setStatus` → `apply` |

`HookStateMachine` is unchanged. `ControlService` delegates the `.setStatus`
case to it rather than reimplementing the transitions.

### Source layout

A new `Sources/Control/` holds the port's vocabulary and wire format, shared by
the app target, the CLI target, and the test target:

- `TabColor.swift` (moved from `Sources/Model/`)
- `TintStop.swift` (new)
- `PaneTint.swift` (extracted from `Sources/Model/TabColor+Auto.swift`)
- `ControlCommand.swift` (new)
- `ControlWire.swift` (new: `ControlRequest`, `ControlResponse`)

`TabColor+Auto.swift` stays in `Sources/Model/` because its hash and knockout
logic depends on `GitInfo`. Splitting the extension from its type across
directories is fine in Swift.

`ControlService` and `ControlState` stay in `Sources/Model/` — they are app-side
core, not CLI vocabulary.

Target sources:

| target | sources |
|---|---|
| `montty` (app) | Control, Model, Persistence, View, App, Ghostty |
| `montty-cli` | Control only |
| `montty-unit` | Control, Model, Persistence, Tests |

The CLI compiles `Sources/Control` alone, so it stays small and cannot reach
AppKit.

### Color model

`TintStop` is what actually gets rendered. `TabColor` stays a closed enum
meaning "an ANSI-16 palette slot resolved through the Ghostty theme".

```swift
enum TintStop: Codable, Equatable, Hashable {
    case named(TabColor)
    case hex(RGB)      // validated at parse, encodes back to "#rrggbb"
}

struct PaneTint { let stops: [TintStop] }   // 1-3 stops
```

Hex can only ever originate from an override. Every derived color —
`polynomialHash`, `colorForGitInfo`, `knockout`, `hueFamily`, and `orderedCases`
indexing into `tabPalette` — is exclusively about named slots and keeps taking
`TabColor`. Bolting a `.hex` case onto `TabColor` instead would make
`CaseIterable` a lie, leave `polynomialHash % allCases.count` depending on an
invariant held by convention, and allow a hex value to reach the hash palette.
With `TintStop` the compiler forbids it.

`TintStop.hueFamily` derives from RGB for hex stops, because `paneTint` feeds an
override into `knockout` as a parent stop
(`Sources/Model/TabColor+Auto.swift:129`).

`swiftUIColor` moves to `TintStop`. `TabColorPicker` still renders swatches from
`TabColor.allCases` and reaches rendering through `TintStop.named(color)`.

### Scopes and precedence

All three override scopes become `PaneTint`, so any of them can be a gradient.

| scope | storage |
|---|---|
| surface | `tab.surfaceColorOverrides: [UUID: PaneTint]`, keyed by surfaceID |
| tab | `tab.colorOverride: PaneTint?` |
| repo | `repoColorOverrides: [String: PaneTint]` |

Effective tint for a pane: **surface > tab > repo > git signature > gray**.
`TabColor.resolvedPaneTint` takes one new `surfaceOverride:` argument; the repo
layer is already consulted inside `paneTint(for:overrides:)`.

The sidebar row keeps its existing rule — tab override if set, otherwise the
focused pane's effective tint — which now means a surface override on the
focused pane shows in the sidebar. `Tab.effectivePaneTint` consults
`surfaceColorOverrides[focusedSurfaceID]` first.

`montty tab name` writes `tab.name`, which already wins over `autoName`
permanently, so stickiness comes for free. `--reset` clears it back to the
terminal-title-derived `autoName`.

## Transport

### Socket location

`HookServer.socketPath` moves from `/tmp/montty-hook.sock` to the per-user temp
directory:

```swift
static let socketPath = ProcessInfo.processInfo.environment["MONTTY_SOCKET"]
    ?? NSTemporaryDirectory() + "montty-hook.sock"
```

One name serves both directions. If `MONTTY_SOCKET` is set in the app's own
environment, montty binds there; either way it injects the resolved path into
every surface as `MONTTY_SOCKET`, which is what the wrapper and the CLI already
read.

`NSTemporaryDirectory()` resolves `confstr(_CS_DARWIN_USER_TEMP_DIR)`, which is
mode 0700, owned by the user, per-user, and auto-cleaned. This is the macOS
equivalent of `$XDG_RUNTIME_DIR`, which does not exist on macOS — there is no
systemd to create it. It fixes two problems:

- `/tmp` is world-accessible, so any local process can restyle tabs and drive
  the activity indicator. Already true of hook events today; this change widens
  what those messages can do, so the directory should narrow first.
- `HookServer.start` (`Sources/App/HookServer.swift:47`) unconditionally
  `unlink`s the path before binding. Today `just run` therefore hijacks the
  installed montty's hook socket, and Claude hooks from real panes get routed to
  the dev build. Two users on one machine collide the same way.

`MONTTY_SOCKET` mirrors the existing `MONTTY_SESSION_DIR` escape hatch.
`just run` and `just run-bg` set it so a dev build never steals the installed
app's socket.

The shell wrapper needs no change: it reads `$MONTTY_SOCKET` from the injected
environment rather than hard-coding a path. Shells started before an upgrade
hold a stale `$MONTTY_SOCKET`; that clears on the next shell.

Path length is within the 104-byte `sun_path` limit that
`strlcpy(pathPtr, src, 104)` in `start()` already assumes:
`/var/folders/xx/…/T/montty-hook.sock` lands near 56 characters.

### Wire format

One request per connection. The server replies, then closes. The client reads
until EOF.

Request:

```json
{"v":1,"cmd":"set","surface":"<MONTTY_SURFACE_ID>","scope":"surface",
 "prop":"color","value":["neutralBright","#1a7f37"]}
```

One property per request, matching one `ControlCommand` per request. `prop` is
`color`, `name`, or `status`; `scope` is present only for `color`. A `value` of
`null` is the clear form that `--reset` sends.

Response:

```json
{"ok":true}
{"ok":false,"error":"unknown surface"}
```

`{"v":1,"cmd":"info","surface":"…"}` returns:

```json
{
  "ok": true,
  "surface_id": "…",
  "leaf_id": "…",
  "tab_id": "…",
  "tab_name": "montty/",
  "tab_name_is_override": false,
  "scopes": {
    "surface": {"stops": ["#1a7f37"]},
    "tab": null,
    "repo": {"identity": "/Users/ted/montty", "stops": ["green"]}
  },
  "effective": {"stops": ["neutralBright", "green"]},
  "git": {"repo_name": "montty", "branch": "main", "worktree": null,
          "repo_path": "/Users/ted/montty"},
  "status": "working"
}
```

**Versioning.** `v` is the protocol version, starting at 1. The binary ships
inside the app bundle so they are normally in lockstep, but a stale Homebrew
symlink or a hand-copied binary would otherwise fail cryptically. A `v` higher
than the server understands is rejected with `"montty CLI is newer than the
app"`.

**Backward compatibility.** A message with neither `v` nor `cmd` is a legacy
hook event and takes the existing `ClaudeHookMessage.parse` path verbatim. A
wrapper from an older app version keeps working.

**Concurrency.** The accept loop is serial today and never waits, so that is
safe. Replying to `info` requires waiting on a main-thread hop, and a serial
loop blocking there would stall hook delivery. The accept loop dispatches each
connection to a concurrent queue; the per-connection handler hops to main and
waits on a semaphore with a 1s timeout.

## The binary

A new xcodegen target `montty-cli`, product name `montty`, embedded at
`Montty.app/Contents/MacOS/montty`. Foundation only.

The app injects `MONTTY_BIN` — derived from `Bundle.main.bundleURL` — alongside
the three environment variables it already sets at
`Sources/App/AppDelegate.swift:176`, `:246`, and `:592`, so a montty pane can
always reach the binary by absolute path regardless of PATH.

Distribution: the cask template inlined at `.github/workflows/release.yml:190`
gains `binary "#{appdir}/Montty.app/Contents/MacOS/montty"` and drops
`depends_on formula: "jq"`, which the rewritten wrapper no longer needs. A
`just install-cli` recipe symlinks the dev build for local work.

### Grammar

```
montty surface color <spec>          montty surface color --reset
montty tab     color <spec>          montty tab     color --reset
montty repo    color <spec>          montty repo    color --reset
montty tab     name  <text>          montty tab     name  --reset
montty surface status <state>        state: working | waiting | idle | clear
montty hook <event>                  event: session-start | prompt-submit |
                                            pre-tool-use | notification |
                                            stop | session-end
montty info
montty --version
```

`<spec>` is 1 to 3 comma-separated stops. A stop is either a palette name or a
6-digit hex value with or without a leading `#`, since bash treats a bare `#` as
a comment introducer. Names match case-insensitively with `-` and `_` stripped,
so `brightGreen`, `brightgreen`, and `bright-green` are the same stop. Three-digit
hex shorthand is rejected; the error names the expected form.

`montty repo` resolves repo identity server-side from the calling surface's
effective directory — Claude's reported cwd when present, otherwise the shell
pwd — so the client never needs git.

Examples:

```bash
montty tab name "MR !123 fix auth"
montty tab color "#1a7f37"
montty surface color neutralBright,green
montty tab color blue,brightMagenta,cyan
montty info | jq -r .git.branch
```

### Exit codes

| exit | meaning |
|---|---|
| 0 | ok |
| 1 | server rejected it (unknown surface, unsupported cmd, protocol version) |
| 2 | not inside a montty pane (`$MONTTY_SURFACE_ID` unset) |
| 3 | montty is not running (socket missing, connect failed) |
| 64 | usage error: bad color spec, unknown scope or verb |

One line to stderr, no stack traces, so a skill never has to parse output. Color
specs validate client-side before anything reaches the socket, so a typo costs
an exit 64 and no round trip. Connect and read each time out at 1s.

`montty hook` is the exception: it is fire-and-forget, does not wait for a
reply, and **exits 0 even on failure**, because Claude Code surfaces hook errors
and a montty-less environment should not look broken.

## Claude Code fold-in

`montty hook <event>` reads Claude's payload on stdin, extracts `.cwd`, and
sends the existing wire format — `{"event":…,"surface":…,"cwd":…}` — so
`HookServer`'s legacy path is untouched.

That collapses the heredoc at `project.yml:82` to a static settings JSON. No
`jq` to build it, no `nc` to send it, and the `command -v jq` guard disappears:

```
"command": "\"$MONTTY_BIN\" hook pre-tool-use"
```

The `INPUT=$(cat); (… | nc …) &` pattern goes away too. A local socket connect
either succeeds immediately or fails with ENOENT, so there is nothing to
background around.

`montty surface status working|waiting|idle|clear` writes the same state, so
`just check && montty surface status idle` drives the identical indicator.
`clear` removes the entry, matching `session-end`.

### Rename

Once any process can set it, `ClaudeCodeStatus` is a misnomer:

| from | to |
|---|---|
| `ClaudeCodeStatus` | `ActivityStatus` |
| `tab.claudeStates` | `tab.activityStates` |
| `tab.claudeWaitingSince` | `tab.activityWaitingSince` |
| `MinimapPane.claudeCode` | `MinimapPane.activity` |
| `/surfaces` JSON key `claude_code` | `activity` |

`ClaudeHookEvent`, `ClaudeHookMessage`, `HookDirectoryTracker`, and
`tab.claudeDirectories` keep their names: only Claude Code reports a cwd, so
those are genuinely Claude-specific.

`docs/debug-server.md` documents the `claude_code` key and is updated with the
rename.

## Context menu

The current menu has two color entries that look identical but are not.
`Color: montty` (`Sources/View/TabContextMenu.swift:47`) writes
`repoColorOverrides`, recoloring every tab whose focused pane sits in that repo
and persisting across restarts. `Tab Color` (`:58`) writes `tab.colorOverride`
for one tab. With a single tab open in a repo, both produce the same visible
result.

The menu becomes three explicitly labeled scopes:

```
Rename...
Surface Color        >
Tab Color            >
Repo Color: montty   >
Close Tab
```

Each submenu offers the 14 named swatches plus a Reset that appears only when
that scope has an override. `TabColorPicker` takes `currentTint: PaneTint?`
instead of `currentColor: TabColor` and checks a swatch only when the tint is
exactly one named stop. A CLI-set hex or gradient therefore shows no checkmark
but does show Reset — which is how the menu clears anything `montty` set.

The picker stays single-color. Gradients and hex are CLI-only.

## Session persistence

`SessionSnapshot.currentVersion` is 2 today, written and decoded
(`Sources/Persistence/SessionSnapshot.swift:39`) and asserted in tests, but
never branched on. It is decorative, and that has a concrete cost: install the
new build, it writes v3 with gradient arrays; roll the cask back; the old build
hits `decodeIfPresent(TabColor.self)` on `["neutralBright","#1a7f37"]`, throws a
type mismatch, `load()` swallows it (`Sources/Persistence/SessionStore.swift:39`)
and returns nil, and the 8-second autosave then overwrites `session.json`. The
session is lost twice over, silently.

Version 3 changes:

- `colorOverride: TabColor?` becomes `PaneTint?`
- `repoColorOverrides: [String: TabColor]` becomes `[String: PaneTint]`
- `TabSnapshot` gains `leafColorOverrides: [UUID: PaneTint]`, keyed by leaf ID

Leaf ID is the correct key because `restoreSplitNode`
(`Sources/App/AppDelegate.swift:588`) mints fresh `surfaceID`s and
`MONTTY_SURFACE_ID`s on restore but preserves leaf IDs — the same reason
`leafDirectories` works.

Migration is lenient decoding plus a version gate, not stepwise migrators. The
schema is small enough that a per-generation struct chain would be machinery
without payoff.

- **Lenient decode.** `PaneTint`'s decoder accepts either a bare string
  (`"green"`) or an array (`["neutralBright","#1a7f37"]`). One decoder covers all
  three migration points with no per-field version branching.
- **Compatible encode.** A single stop encodes back as a bare string; only real
  gradients write an array. A rolled-back v2 build can still read any session
  that has no gradients in it.
- **Forward-incompat refusal.** A `version` greater than `currentVersion` refuses
  to load rather than decoding partially. This protects from v3 forward; the
  compatible encoding is what protects the rollback to today's build.
- **Corrupt-file quarantine.** If `load()` throws, move the file aside to
  `session.corrupt-<timestamp>.json` before the first autosave. Today a bad parse
  silently destroys the evidence.
- **Version-bump backup.** On the first write at a new version, copy the previous
  file to `session.v<n>.json`.

## Error handling

| condition | behavior |
|---|---|
| `$MONTTY_SURFACE_ID` unset | exit 2, `not running inside a montty pane` |
| socket missing or connect fails | exit 3, `montty is not running` |
| bad color spec | exit 64 client-side, no round trip |
| unknown scope or verb | exit 64 client-side |
| more than 3 stops | exit 64 client-side; `PaneTint.init` also clamps to the first 3 as a safety net |
| unknown surface (stale id after restart) | server replies `{"ok":false,…}`, exit 1 |
| protocol version too new | server replies with a version error, exit 1 |
| any failure under `montty hook` | exit 0, silent |

## Testing

Red/green throughout, per `CLAUDE.md`. Suite stays under 5s.

`Sources/Control` and `Sources/Model` are both compiled by `montty-unit` with no
test host, so the entire port and wire format is pure and unit-testable:

- `TintStop` parse and round-trip: names, case and separator normalization,
  `#rrggbb` with and without `#`, rejection of `#fff`, `#gggggg`, and empty
- `TintStop.hueFamily` derived from RGB
- `PaneTint` stop clamp to 3, Codable both directions including
  single-stop-as-string and array forms
- `ControlService.apply` precedence across every combination of surface, tab,
  repo, git, and gray
- `ControlService.apply` for name set and clear, and status set and clear,
  including delegation to `HookStateMachine`
- Session v2 to v3 lenient decode, and the v4 forward-incompat refusal
- `ControlRequest` parse from argv, and decode from JSON, covering the legacy
  no-`cmd` hook path and a `v` mismatch rejection
- Exit code selection as a pure function of outcome

The socket accept loop and AppKit rendering are not unit-testable. Those are
verified through `just inspect-surfaces`, whose `/surfaces` payload is extended
to report the surface-level override alongside the existing tab color.

## Build order

1. `Sources/Control/` with `TintStop`, `PaneTint`, moved `TabColor`, and their
   tests. No behavior change yet.
2. `PaneTint` everywhere: the three override scopes, `resolvedPaneTint`
   precedence, session v3 with lenient decode, quarantine, and backup.
3. `ControlCommand` / `ControlService` / `ControlState`, with the right-click
   menu rewired through it as the first adapter. Three labeled submenus.
4. `ControlRequest` / `ControlResponse`, `HookServer` protocol extension,
   concurrent connection handling, socket relocation, `MONTTY_SOCKET` override.
5. `montty-cli` target, `MONTTY_BIN` injection, `just install-cli`, cask stanza.
6. `montty hook`, `project.yml` wrapper rewrite, `ActivityStatus` rename,
   `montty surface status`, `docs/debug-server.md` update.
