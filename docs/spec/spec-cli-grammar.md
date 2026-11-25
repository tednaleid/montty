# CLI Grammar, Scoped Settings, and Help

## Goal

Give the `montty` CLI one regular grammar, so every setting is spelled the same
way at every scope, help is specific to the command being typed, and a new
setting or a new scope for an existing one is a short declaration rather than
new parsing code.

Terms used here (Scope, Setting, Override, Surface Tint, Tab Tint, Minimap
Visibility, Surface) are defined in [GLOSSARY.md](../../GLOSSARY.md).

## Grammar

```
montty <scope> <setting> [<value> | --reset]
montty <verb> [<argument>]
```

Scopes: `surface`, `tab`, `repo`, `app`. The first three are resolved from the
surface the command runs in. `app` is the whole app, across all windows.

Verbs: `info`, `hook`, `install-hooks`, `uninstall-hooks`. They are unchanged.

A setting's name says what is drawn and never changes with the scope. A name
may contain a scope-sounding word (`surface-tint-strength`,
`tab-tint-strength`); it names the thing styled, not whose value is set.

### Settings and the scopes each accepts

| setting | surface | tab | repo | app | value |
|---|---|---|---|---|---|
| `color` | yes | yes | yes | | 1 to 3 color stops |
| `name` | yes | yes | | | text |
| `status` | yes | | | | `working`, `waiting`, `idle`, `clear` |
| `resume-command` | yes | | | | a shell command |
| `surface-tint-strength` | yes | yes | yes | yes | 0 to 0.5, default 0.12 |
| `tab-tint-strength` | yes | yes | yes | yes | 0 to 0.3, default 0.12 |
| `minimap` | | yes | | yes | `always`, `never`, or conditions; default `always` |
| `minimap-height` | | yes | | yes | 40 to 200 points, default 90 |

Naming a scope a setting does not accept is a usage error that lists the scopes
it does accept.

### The three forms

- `montty <scope> <setting> <value>` sets the value at that scope.
- `montty <scope> <setting> --reset` removes the override at that scope. At the
  `app` scope it returns the setting to its default.
- `montty <scope> <setting>` prints what that scope resolves to: its own value
  if it has one, else the next wider scope's, out to the app value or default.
  `color` is the exception: a scope with no color of its own prints
  `not set (effective <color>)`, because a color can also come from the git
  signature, which belongs to no scope.

A value that starts with `-` is written after `--`, as in
`montty tab name -- -draft`.

Every setting has all three forms. `status` also clears with `clear`, as now,
and its read form prints nothing when the surface has no activity status.

### Removed spellings

`montty tint-strength`, `montty minimap`, `montty minimap-height`, and
`montty tab-tint-strength` at the top level are gone. They are usage errors
like any other unknown first word. `montty tint-strength` had shipped; montty
is before 1.0 and this is an accepted breaking change.

## Resolution

A setting resolves by starting from a surface and taking the first value found
at: that surface, its tab, its repo, the app.

- **Surface tint strength** for a surface starts from that surface.
- **Tab tint strength** for a tab starts from the tab's focused surface (the
  last focused one, for a tab that is not active). This is the surface the
  tab's color already comes from, so a tab's wash takes its color and its
  strength from the same place, and both can change when focus moves within
  the tab. The active and hidden-minimap multipliers in
  [spec-minimap-visibility.md](./spec-minimap-visibility.md) apply to the
  resolved value.
- **Minimap visibility** and **minimap height** resolve tab, then app. They
  have no surface or repo scope, so a row's height never depends on which
  surface in the tab has focus.

- **Name** resolves surface, then tab, then the automatic name. A tab shows
  the name of its focused surface when that surface has one, so a surface name
  beats a tab name, and the name shown for a tab can change when focus moves
  within it.

`color` keeps its existing resolution and storage.

## Help

Parsing, help, and usage errors come from
[swift-argument-parser](https://github.com/apple/swift-argument-parser), so
their layout and wording are the library's.

`--help` or `-h` after any part of a command prints help for that part and
exits 0. `montty help <scope> <setting>` does the same.

| command | prints |
|---|---|
| `montty --help` | overview: one line per scope and per verb |
| `montty tab --help` | the settings the `tab` scope accepts, one line each |
| `montty tab color --help` | the color forms, the stop syntax, and the palette |
| `montty app surface-tint-strength --help` | what it styles, its range and default |
| `montty install-hooks --help` | that verb's usage |

The palette appears only in help for `color`.

`montty hook` is recognised before the library sees the arguments. A hook must
never print, so it never answers `--help`, and it skips arguments it does not
know.

### Usage errors

A usage error prints one `Error:` line, the usage line of the part of the
command that was recognised, and a pointer to that part's `--help`. It exits
64.

```
$ montty app surface-tint-strength 0.9
Error: not a number between 0.0 and 0.5: "0.9"
Usage: montty app surface-tint-strength [<value>] [--reset]
  See 'montty app surface-tint-strength --help' for more information.
```

A setting named at a scope that does not accept it is reported as an
unexpected argument, with a pointer to that scope's help, which lists what the
scope does accept.

### Completions

The library can print a completion script for zsh, bash, or fish
(`montty --generate-completion-script zsh`). montty does not install one.

## Structure

The commands are declared in `Sources/Control` as swift-argument-parser
command types. Each setting is one type, generic over the scope, and each
scope lists the settings it accepts, so the table above is the declaration.
A parsed command yields the same `ControlCommand` values as before; nothing
below the parser changes.

The library is montty's only Swift package dependency. `project.yml` pins an
exact version, because the generated Xcode project and its resolved-package
file are not checked in.

Whether to launch the GUI or parse a command is still decided first, by
montty's own code, as is `montty hook`.

Scoped values for the two strengths and the minimap settings are stored and
resolved by one mechanism: a value per surface, per tab, per repo, and for the
app. `ControlService` applies a set or reset at any scope and answers a read,
with the repo and app values passed in beside the tab's state, the way
`repoColorOverrides` is. `Sources/App` holds the app and repo values and holds
no decisions about them.

### Persistence

In the session JSON file:

- App values sit on `SessionSnapshot`. `surfaceTintStrength`,
  `minimapVisibility`, and `minimapHeight` keep their keys.
- Repo overrides are keyed by repo identity, beside `repoColorOverrides`.
- Tab overrides sit on `TabSnapshot`.
- Surface overrides sit on `TabSnapshot` keyed by leaf ID, like
  `leafColorOverrides`, because leaf IDs survive a restore.

Every key is optional when decoding, and a value this montty cannot read falls
back to the next wider scope rather than failing the session.

### Menus

The strength overrides are CLI only. View > Minimaps and the tab's Minimap
submenu are unchanged, and View > Toggle Surface Tint still switches the
surface tint on and off for the whole app.

### `montty info`

`montty info` reports, for each scoped setting, the value at each scope that
has one and the effective value:

```json
"settings": {
  "surface_tint_strength": {"tab": 0.2, "app": 0.12, "effective": 0.2},
  "tab_tint_strength": {"app": 0.12, "effective": 0.12},
  "minimap": {"tab": "never", "app": "always", "effective": "never"},
  "minimap_height": {"app": 90, "effective": 90}
}
```

The keys are snake-cased like the rest of `montty info`. A scope with no value
is absent. This replaces the `minimap` object. The read form of a setting is
answered from this object.

## Order of work

1. **CLI restructure.** The library, the `app` scope, the renamed settings,
   help at every level, the read form for every setting, and the `settings`
   object in `montty info` that the read form is answered from. The strengths
   and `minimap-height` are still held at the app scope only, and `name` at
   the tab scope only. Nothing drawn in the app changes.
2. **Scoped overrides.** Surface, tab, and repo overrides for the two
   strengths, the tab scope for `minimap-height`, the surface scope for
   `name`, their session storage, and their values at each scope in
   `montty info`.

## Testing

**Unit tests (red/green)**:
- Every setting at every scope it accepts: set, reset, and read.
- Every setting at a scope it does not accept is a usage error.
- `--help` and `-h` at each depth; `hook` with `--help` among its arguments
  still parses as a hook.
- Each usage error exits 64 and names the recognised part of the command.
- The removed top-level spellings are usage errors.
- Resolution: surface over tab over repo over app for each strength; tab tint
  strength follows the tab's focused surface; a surface name beats a tab
  name; reset falls back one scope.
- Session round trip for an override at every scope, and decoding a session
  that has none.

**Runtime verification** (debug server, `just inspect-*`):
- Set a surface tint strength at each scope and see only the surfaces in that
  scope change; reset each and see the wider value return.
- Set a tab tint strength at the surface scope in a split tab and see the
  tab's wash change as focus moves.
- Set a tab's minimap height and see only that tab follow.
- Read each setting back with no value, and through `montty info`.
- Relaunch and see every override restored.
