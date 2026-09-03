# README screenshot harness

One command that rebuilds every image in the README from a demo world montty
owns, so the pictures can be re-shot whenever the UI moves instead of being
recreated by hand.

## Motivation

`docs/screenshot.png` and `docs/screenshot-easymotion.png` were taken on
2026-03-23. Montty has since gained multiple windows, repo colors, gradient
tints, the `montty` CLI, and open-in-editor, and the README neither shows nor
mentions any of them.

Both images also carry data that does not belong in a public repo: a tab titled
with the author's username, personal directory paths under
`~/Documents/archives/...`, and a Claude Code banner naming the account's plan
tier and model.

The reason they went stale is that re-shooting them is a manual chore. It means
arranging tabs, splits, colors, and running processes by hand, then cropping the
result. A layout that a script can rebuild in one command is a layout that stays
current.

## Goals

- One command regenerates every README image.
- The same layout, colors, and dimensions on every run and on any machine.
- Nothing personal in frame.
- Show the features the README claims, including the ones added since March.
- Make hand-picking colors cheap, so the palette can be tuned after seeing it.

## Non-goals

- Pixel-identical output. The Claude pane holds a real session, and its reply
  text differs between runs.
- Capturing the real right-click color menu. macOS menus are separate windows at
  their own level, so a window capture never contains one. A region capture
  would need stable coordinates and the Screen Recording permission, which
  varies per machine. A pane running `montty --help` shows the same palette
  names at no cost.
- Changes to the app. Seeding the session file sets window geometry, so the
  harness needs no new debug endpoint.
- A general screenshot framework. This serves the README. `just inspect-*` and
  the `test-app` skill remain the tools for ad hoc verification.
- Running in CI. The harness is run by hand when the UI changes.

## Isolation

The harness drives only the debug build under `/tmp/montty-build`, with its own
socket and session directory, so it cannot reach a montty hosting a real shell,
and `just stop` stays scoped by executable path.

| Variable | Pins |
|---|---|
| `XDG_CONFIG_HOME` | Ghostty theme, font, and font size, from a demo config the harness writes |
| `ZDOTDIR` | a minimal zsh rc: fixed prompt, no history, no plugins, no user config |
| `MONTTY_SESSION_DIR` | the seeded session, away from the installed app's |
| `MONTTY_SOCKET` | the hook and control socket, away from the installed app's |

`HOME` is deliberately left alone. Claude Code stores its login under the real
home, and a fresh `HOME` makes it report `Not logged in`, which would replace the
live session in the hero shot with a login prompt.

That leaves one exposed surface: Claude Code's startup banner, which prints the
model, effort, and plan tier. The scripted interaction runs long enough to push
the banner out of the viewport before capture, so the pane shows a conversation
rather than a masthead.

## Determinism

Tab colors are pure functions of one string. `TabColor.colorForGitInfo` takes
`repoIdentity`, which is `repoPath + (worktreeName ?? "")`, and indexes the
palette by `polynomialHash`. The leading gradient stop comes from `knockout`,
which indexes by an independent FNV-1a hash after removing every hue family
already in use. Nothing consults tab order, creation time, or the other open
tabs, so the same directory always yields the same tint.

Because the identity is an absolute path, the demo tree lives at a fixed
`/private/tmp/montty-demo`, alongside the existing `/tmp/montty-build`
convention. A tree under `$HOME` would hash the username into every color and
produce different results on a different machine.

The path is spelled `/private/tmp` rather than `/tmp` because macOS resolves one
to the other. montty seeds a pane's directory from the session file, but only
until that pane's own shell reports a pwd, and a shell started there reports the
resolved `/private/tmp` form. Spelling it `/tmp` would leave the seeded session,
the reported directory, and the `repoColorOverrides` key disagreeing, which
silently drops every hand-picked repo color the moment the shell starts.

`TabInfo` renders a directory that is not a direct child of home as its
basename with a trailing slash, so `/private/tmp/montty-demo/acme-api` displays as
`acme-api/`. No username and no path depth ever reaches the sidebar, and no
`$HOME` substitution is needed anywhere in the fixtures.

The rendered RGB for each palette slot comes from the Ghostty theme, which the
demo config pins. Window size and sidebar width come from the seeded session.
Pane text comes from fixture files. The only varying element is the Claude
reply.

## The demo world

The harness materializes `/private/tmp/montty-demo` on every run:

```
/private/tmp/montty-demo/
  config/ghostty/config     pinned theme, font, font-size
  zdotdir/.zshrc            fixed prompt, no history
  session/session.json      generated from the demo spec
  repos/
    acme-api/.git/HEAD      ref: refs/heads/main
    acme-api/...            fixture files the panes cat
    web-ui/.git/HEAD        ref: refs/heads/feature/checkout
    infra/.git/HEAD         ref: refs/heads/main
    acme-api-hotfix/.git    a .git file pointing at acme-api, for a worktree label
  scratch/                  a non-repo directory, to show the gray no-repo case
```

`GitInfo.from` walks for `.git` and reads `HEAD` with filesystem calls only. It
never shells out, so a demo repo costs one `mkdir` and one `echo` and needs no
commits, no objects, and no `git` binary.

## The demo spec

Rather than a hand-maintained `session.json`, the script carries a readable
table and expands it. Editing a color means changing one line next to a tab
name, instead of hunting through UUID-keyed flat arrays. `leafColorOverrides`
and `leafDirectories` serialize as alternating key and value entries, which is
correct for the app and unreadable for a human.

```python
TABS = [
    Tab(name="acme-api/",  repo="acme-api",  color=AUTO,  panes=1),
    Tab(name="MR !123 fix auth", repo="acme-api", color="neutralBright,green",
        panes=3, focused_pane=0,
        statuses={1: "working", 2: "waiting"}, claude_pane=0),
    ...
]
```

UUIDs are constants in the spec, not generated, so a rerun produces a session
file identical to the last one.

### The roster

Window one carries six tabs, each earning its place by showing something the
README claims:

| Tab | Directory | Color | Shows |
|---|---|---|---|
| `acme-api/` | `repos/acme-api` | automatic | the git signature gradient, derived from repo identity |
| `MR !123 fix auth` | `repos/acme-api` | `neutralBright,green` | a custom name and a hand-set gradient, three panes, the live Claude session, and the `working` and `waiting` dots |
| `web-ui/` | `repos/web-ui` | automatic | a second repo's signature, and a two-pane split |
| `acme-api-hotfix/` | `repos/acme-api-hotfix` | automatic | a worktree carrying its parent's leading stop with its own trailing stop |
| `infra/` | `repos/infra` | hand-picked | a repo color override beating the hash |
| `scratch/` | `scratch` | gray | the no-repo case, and the pane that runs `montty --help` |

The second tab is the focused one, so it is what the hero and jump images show
expanded. Window two carries two tabs of its own pointing at the same repos,
since tabs never move between windows and each window owns its own list.

## Orchestration

`scripts/screenshots.py`, with a `uv run --script` shebang, invoked by
`just screenshots`:

1. `just build`, then stop any debug montty still running.
2. Materialize the demo world and expand the spec into `session.json`.
3. Launch the debug build with the four environment variables above.
4. Poll `/surfaces` until it answers.
5. Verify the restored layout against the spec: tab count, names, split counts,
   and resolved colors, read back from `/surfaces`. A mismatch aborts with the
   difference rather than shooting a wrong picture. This is what keeps a session
   schema change from silently degrading the images.
6. Fill panes by typing `cat` of the fixture files over `/type` and `/key`.
7. Set the activity dots by invoking the real `montty` binary with an explicit
   `MONTTY_SURFACE_ID` and `MONTTY_SOCKET`, taken from `/surfaces`. The CLI
   requires only those two variables, so it drives the app from outside a pane.
8. Run the Claude exchange in the designated pane.
9. Capture in an order that respects what each step mutates: the hero first,
   since it needs the focused tab untouched and jump mode inactive; then jump
   mode, captured and dismissed with `escape`; then window two, captured through
   its own surface id; then `goto_tab` to the `scratch/` tab for the CLI image,
   which is last because it moves the focus.
10. Post-process and write into `docs/`.
11. Stop the app. The demo tree stays behind for inspection; `just
    screenshots-clean` removes it.

## The images

| File | Contents |
|---|---|
| `docs/screenshot.png` | Window one: six colored tabs, the focused tab holding three panes, one running the live Claude session and two carrying `working` and `waiting` dots, with the minimap showing all of it |
| `docs/screenshot-easymotion.png` | The same window with jump mode active, from `POST /jump` |
| `docs/screenshot-windows.png` | Two windows side by side, showing one process owning both |
| `docs/screenshot-cli.png` | A pane running `montty --help`, showing the palette swatches and the command grammar |

`/screenshot?surface=` captures one window at a time, so the two-window image is
built by capturing each window and compositing them with Pillow. That avoids the
Screen Recording permission a real two-window screen grab would require, and
both halves remain genuine captures of the same running process.

A post-process pass downscales the 2x captures to roughly 1400px wide. The
current pair are about 600KB each at full retina size.

## Fast iteration

`just screenshots-preview` relaunches with the current spec and shoots only the
hero image, skipping the Claude exchange. Trying a palette costs seconds and no
API calls, which is what makes hand-picking colors practical after seeing the
first result.

## Delivery order

The demo world is built and reviewed before anything is automated around it.
The first milestone materializes the tree, expands the spec into a session, and
launches montty on it, and stops there. That puts the real window on screen with
the real directories, names, splits, and colors, which is the only honest way to
judge whether the palette is pleasing and the roster reads well.

Tweaks to directories, names, and colors happen at that gate, against a live
window, before any capture, compositing, or Claude orchestration is written. The
later milestones then automate a layout that is already settled, rather than
producing four images that need reshooting once the colors change.

## README prose

The images land alongside prose corrections in the same effort:

- Multiple windows: one process, `Cmd-N`, tabs stay in their window.
- The `montty` CLI, linking `docs/montty-cli.md`.
- Repo colors and gradient tints, and that colors resolve surface, then tab,
  then repo, then the git signature.
- Open the focused pane's directory in an editor.
- Captions matching the new images.

## Risks

- The Claude pane costs a small number of API calls per full run, and its reply
  text differs between runs.
- Claude Code may show a first-run trust prompt for a directory it has not seen.
  The harness dismisses it with a keypress.
- The real `~/.claude` settings apply to that session, so the global hooks fire,
  which is what lights the status indicator honestly, and the global CLAUDE.md
  may shape how the reply reads.
- Capturing raises the demo window to the front. The window belongs to the debug
  build, never to a montty hosting a real shell.

## Testing

The harness verifies itself at step 5, comparing the restored layout against the
spec before any capture, so drift fails loudly. Beyond that it is tooling whose
output is judged by looking at it. No unit tests are added to the Swift suite,
which has no way to render an AppKit window headlessly.
