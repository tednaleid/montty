# Minimap Visibility and Height

## Goal

Let users hide the minimap on tab rows so more tabs fit in the sidebar, either
everywhere or per tab, and let them set how tall a visible minimap is. A row
without its minimap is roughly 60pt tall against roughly 155pt with it.

Terms used here (Minimap, Minimap Visibility, Split Condition, Status
Condition, Activity Status, Surface) are defined in
[GLOSSARY.md](../../GLOSSARY.md).

## Minimap visibility

### Values

A minimap visibility is one of:

- `always` -- the row shows the minimap
- `never` -- the row does not show the minimap
- a non-empty set of conditions -- the row shows the minimap while at least one
  condition holds

Conditions:

| condition | holds while |
|---|---|
| `split` | the tab has more than one surface |
| `status` | any surface in the tab has an activity status |

The status condition counts every state, `idle` included, and does not care
whether a Claude Code hook or `montty surface status` set it. Counting `idle`
means the minimap appears when a session starts and disappears when it ends,
not each time the program starts and stops working.

Conditions combine with OR. The set is open to more conditions later.

### Scopes

- **Global**: one value for the whole app, across all windows. Default
  `always`, so a session that predates the setting looks the same as before.
- **Tab override**: optional. A tab with an override uses it; a tab without one
  uses the global value. Resetting removes the override.

The effective visibility of a tab is its override if it has one, else the
global value.

### Persistence

Both live in the session JSON file. The global value sits beside
`surfaceTintEnabled` and `surfaceTintStrength` in `SessionSnapshot`. The tab
override sits in `TabSnapshot`. Both keys are optional when decoding, so a
session written before they existed still loads.

### CLI

```
montty app minimap <always|never|split|status|split,status>
montty app minimap --reset
montty tab minimap <always|never|split|status|split,status>
montty tab minimap --reset
```

`montty app minimap` sets the global value and `--reset` returns it to `always`.
`montty tab minimap` sets the override on the tab holding the calling surface
and `--reset` removes it. Conditions are a comma-separated list in any order.
An unknown value, an empty list, or `always`/`never` mixed with a condition is
a usage error (exit 64).

`montty info` reports the tab's override (absent when unset) and its effective
visibility.

### Menus

- **View > Minimaps** sets the global value.
- **Minimap** submenu in the tab's right-click menu sets the tab override.

Both list: Always, Never, a separator, then checkable When Split and When
Status. The tab submenu has Use Default first, checked when the tab has no
override. Checking a condition while Always or Never is selected replaces it
with that one condition. Unchecking the last condition selects Never.

No keyboard shortcuts.

### What a hidden minimap takes with it

- The row shows no activity status. A user who wants it adds the status
  condition.
- There is no click target for a specific surface. Clicking the row selects the
  tab, which focuses the surface that was last focused there, or the first
  surface in tree order when none is recorded.

### Tab tint

Every row is washed with the tint gradient of its tab's focused surface. A row
with its minimap hidden gets a stronger wash, because it has no minimap
rectangle to carry the color. A row with its minimap showing gets a weaker one,
so the surfaces drawn on top still stand out.

| row | active tab | other tabs |
|---|---|---|
| minimap hidden | 0.40 | 0.20 |
| minimap showing | 0.15 | 0.12 |

Those are the defaults. The tab tint strength is one app-wide value, stored in
`SessionSnapshot`, default 0.12, range 0 to 0.3. It is the strength of a row
that is not active and shows its minimap, and the other three scale from it in
the proportions above, so 0 turns the wash off and 0.3 makes the strongest row
fully opaque. CLI only:

```
montty app tab-tint-strength <value>
montty app tab-tint-strength --reset
```

A value outside the range, or not a number, is a usage error (exit 64).

### Changes over time

When a condition starts or stops holding, the row changes height at once. There
is no delay and no hysteresis.

## Jump mode with a hidden minimap

Opening jump mode never changes any row's size or any tab's minimap visibility.

- **Tab with a visible minimap**: every surface gets a label, drawn on its
  minimap rectangle.
- **Active tab with a hidden minimap**: every surface gets a label, drawn large
  on the surface itself. The row draws no badge.
- **Non-active tab with a hidden minimap**: the tab contributes one jump target,
  its focused surface (first in tree order when none is recorded). The label is
  drawn as one small badge over the row, right-aligned and vertically centered,
  on top of the name and git text.

Label priority is unchanged: the active tab's surfaces first, then the other
tabs by position. A hidden-minimap tab takes one slot in that order.

The target list is built without reference to sidebar width or badge width.

## Minimap height

- App-wide, across all windows. Stored in `SessionSnapshot`. Default 90 points.
- Range 40 to 200 points. A value outside the range, or not a number, is a
  usage error (exit 64).
- CLI only:

```
montty app minimap-height <points>
montty app minimap-height --reset
```

- No menu item and no per-tab value.
- The activity indicator and jump badge keep their fixed sizes at every height.
  In a short minimap with several stacked surfaces they can overflow their
  rectangle.

## Structure

Pure model, unit-tested without AppKit or SwiftUI:

- The minimap visibility type, its parsing from and rendering to the CLI text
  form, and its Codable form.
- Effective visibility: tab override over global.
- Whether a tab's row shows its minimap, given the effective visibility, the
  surface count, and the tab's activity states.
- The jump target list, given the tabs, the active tab, and which tabs show
  their minimap.

`ControlService` applies the tab override and the app values alike. The app
values are passed in beside the tab's state, held on `AppDelegate`, and cross
the use case boundary as data on save and restore. `Sources/View` reads the
results and holds no decisions. The grammar these commands are spelled in is in
[spec-cli-grammar.md](./spec-cli-grammar.md).

The debug server reports each tab's override, effective visibility, and whether
its minimap is showing, plus the global value and the minimap height.

## Testing

**Unit tests (red/green)**:
- Parsing: each value, conditions in either order, and each usage error.
- Session round trip for the global value, the tab override, and the height,
  and decoding a session that has none of them.
- Shows-minimap for `always`, `never`, `split`, `status`, and `split,status`
  against one surface, several surfaces, no status, and each status state.
- Override beats global; reset falls back to global.
- Jump targets: a hidden non-active tab yields one target at its focused
  surface; falls back to the first surface; the active tab yields all of its
  surfaces whether or not its minimap shows; priority order holds.
- Height: default, bounds, and reset.

**Runtime verification** (debug server, `just inspect-*`, the `test-app` skill):
- Set the global value and a tab override from the CLI and from each menu, and
  read both back.
- Split a single-surface tab under `split` and see the minimap appear; close
  the split and see it go.
- Set and clear a status under `status` and see the same.
- Open jump mode with hidden minimaps: row heights do not change, a hidden
  non-active tab shows one right-aligned badge, and typing it lands on that
  tab's focused surface.
- Change the height and see every visible minimap follow.
- Relaunch and see all three settings restored.
