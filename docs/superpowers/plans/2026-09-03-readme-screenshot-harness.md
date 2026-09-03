# README screenshot harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command that rebuilds every README image from a demo world montty owns, with a review gate after the layout is on screen and before any capture code is written.

**Architecture:** A single `uv` script materializes a demo tree under `/private/tmp/montty-demo`, expands a declarative tab roster into a v4 `session.json`, and launches the debug build against it with four environment variables that pin the theme, prompt, session, and socket. Later phases drive pane content over the debug HTTP server, set activity dots through the real `montty` CLI, capture windows one at a time, and composite them with Pillow.

**Tech Stack:** Python 3.12 via `uv run --script`, stdlib `unittest`, Pillow for compositing only, the montty debug HTTP server on localhost:9876, and `just` recipes.

**Spec:** `docs/superpowers/specs/2026-09-03-readme-screenshot-harness-design.md`

## Global Constraints

- Demo root is exactly `/private/tmp/montty-demo`. Tab colors hash the absolute repo path, so this path is load-bearing for deterministic colors and must not become `$HOME`-relative.
- `HOME` is never overridden. Claude Code's login lives there, and a fresh `HOME` makes it report `Not logged in`.
- Only the debug build at `/tmp/montty-build` is ever launched, always with its own `MONTTY_SOCKET` and `MONTTY_SESSION_DIR`.
- Session JSON is version 4. Encodings, verbatim from the app: a leaf node is `{"type": "leaf", "leaf": {"id": UUID, "surfaceID": UUID}}`; a split is `{"type": "split", "branch": {"id": UUID, "orientation": "horizontal"|"vertical", "ratio": Double, "first": Node, "second": Node}}`; `horizontal` means left and right, `vertical` means top and bottom; `leafDirectories` and `leafColorOverrides` are flat arrays alternating UUID string and value; a one-stop `PaneTint` encodes as a bare string, two or three stops as an array of strings.
- A tab with no custom name stores `"name": ""`. `TabInfo` then derives the display name, rendering any directory that is not a direct child of home as its basename with a trailing slash.
- `scripts/montty_demo.py` uses an underscore so the test file can import it, and imports Pillow lazily inside the compositing function so the stdlib-only tests run without dependencies.
- No emoji, no em-dashes, no hyperbole in any file this plan creates.
- Every file starts with two `ABOUTME:` comment lines.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/montty_demo.py` | Create: the roster, session generation, world materialization, launch, verification, content driving, capture, compositing, behind subcommands |
| `scripts/test_montty_demo.py` | Create: stdlib `unittest` coverage of the pure session and world generation |
| `justfile` | Modify: add `demo`, `screenshots`, `screenshots-preview`, `screenshots-clean` |
| `docs/screenshot.png` | Modify: regenerated hero image |
| `docs/screenshot-easymotion.png` | Modify: regenerated jump image |
| `docs/screenshot-windows.png` | Create: two windows composited |
| `docs/screenshot-cli.png` | Create: `montty --help` pane |
| `README.md` | Modify: image swap plus prose for multiple windows, the CLI, repo colors, gradients, open-in-editor |

---

## Phase 1: the demo world and the review gate

### Task 1: Roster and session generation

**Files:**
- Create: `scripts/montty_demo.py`
- Test: `scripts/test_montty_demo.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `DEMO_ROOT: Path`, `Tab` and `Window` dataclasses, `WINDOWS: list[Window]`, `REPO_OVERRIDES: dict[str, list[str]]`, `demo_uuid(key: str) -> str`, `build_session() -> dict`.

- [ ] **Step 1: Write the failing test**

```python
# ABOUTME: Stdlib unittest coverage for the montty demo world generator, run
# ABOUTME: without dependencies so it stays cheap to execute.
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import montty_demo as demo


class BuildSessionTest(unittest.TestCase):
    def setUp(self):
        self.session = demo.build_session()

    def test_is_version_four_with_two_windows(self):
        self.assertEqual(self.session["version"], 4)
        self.assertEqual(len(self.session["windows"]), 2)

    def test_first_window_carries_the_six_tab_roster(self):
        names = [t["name"] for t in self.session["windows"][0]["tabs"]]
        self.assertEqual(names, ["", "MR !123 fix auth", "", "", "", ""])

    def test_auto_named_tabs_store_an_empty_name(self):
        first = self.session["windows"][0]["tabs"][0]
        self.assertEqual(first["name"], "")

    def test_leaf_directories_are_flat_alternating_pairs(self):
        first = self.session["windows"][0]["tabs"][0]
        flat = first["leafDirectories"]
        self.assertEqual(len(flat), 2)
        self.assertEqual(flat[1], "/private/tmp/montty-demo/repos/acme-api")

    def test_three_pane_tab_nests_a_vertical_split_inside_a_horizontal_one(self):
        layout = self.session["windows"][0]["tabs"][1]["splitLayout"]
        self.assertEqual(layout["type"], "split")
        self.assertEqual(layout["branch"]["orientation"], "horizontal")
        self.assertEqual(layout["branch"]["first"]["type"], "leaf")
        inner = layout["branch"]["second"]
        self.assertEqual(inner["type"], "split")
        self.assertEqual(inner["branch"]["orientation"], "vertical")

    def test_three_pane_tab_lists_all_three_directories(self):
        tab = self.session["windows"][0]["tabs"][1]
        self.assertEqual(len(tab["leafDirectories"]), 6)

    def test_gradient_override_encodes_as_an_array_of_stops(self):
        tab = self.session["windows"][0]["tabs"][1]
        self.assertEqual(tab["colorOverride"], ["neutralBright", "green"])

    def test_repo_override_is_keyed_by_absolute_repo_path(self):
        overrides = self.session["repoColorOverrides"]
        self.assertIn("/private/tmp/montty-demo/repos/infra", overrides)

    def test_uuids_are_stable_across_calls(self):
        again = demo.build_session()
        self.assertEqual(
            json.dumps(self.session, sort_keys=True),
            json.dumps(again, sort_keys=True),
        )

    def test_focused_leaf_belongs_to_its_own_tab(self):
        for window in self.session["windows"]:
            for tab in window["tabs"]:
                leaf_ids = set(tab["leafDirectories"][0::2])
                self.assertIn(tab["focusedLeafID"], leaf_ids)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test_montty_demo.py`
Expected: FAIL with `ModuleNotFoundError: No module named 'montty_demo'`

- [ ] **Step 3: Write minimal implementation**

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
# ABOUTME: Builds the montty demo world, seeds a session, and drives the app to
# ABOUTME: regenerate every screenshot the README uses.
import json
import uuid
from dataclasses import dataclass, field
from pathlib import Path

DEMO_ROOT = Path("/private/tmp/montty-demo")
REPOS = DEMO_ROOT / "repos"
NAMESPACE = uuid.UUID("6f0d5a5e-3b1a-4f27-9c1c-0b6f4b6f9a10")


def demo_uuid(key: str) -> str:
    """Stable UUIDs from readable keys, so a rerun regenerates the same file.
    Uppercase because Swift's uuidString is, and later tasks compare these
    against ids the debug server reports."""
    return str(uuid.uuid5(NAMESPACE, key)).upper()


@dataclass
class Tab:
    key: str
    directory: str
    name: str = ""
    color: list[str] | None = None
    panes: int = 1
    focused_pane: int = 0
    statuses: dict[int, str] = field(default_factory=dict)
    claude_pane: int | None = None
    content: dict[int, str] = field(default_factory=dict)


@dataclass
class Window:
    key: str
    frame: dict[str, float]
    tabs: list[Tab]
    active_tab: int = 0


WINDOWS = [
    Window(
        key="w1",
        frame={"x": 120, "y": 120, "width": 1400, "height": 900},
        active_tab=1,
        tabs=[
            Tab(key="w1t1", directory=str(REPOS / "acme-api"), content={0: "tree"}),
            Tab(
                key="w1t2",
                directory=str(REPOS / "acme-api"),
                name="MR !123 fix auth",
                color=["neutralBright", "green"],
                panes=3,
                focused_pane=0,
                statuses={1: "working", 2: "waiting"},
                claude_pane=0,
                content={1: "build", 2: "tests"},
            ),
            Tab(key="w1t3", directory=str(REPOS / "web-ui"), panes=2, content={0: "tree", 1: "build"}),
            Tab(key="w1t4", directory=str(REPOS / "acme-api-hotfix"), content={0: "tree"}),
            Tab(key="w1t5", directory=str(REPOS / "infra"), content={0: "tree"}),
            Tab(key="w1t6", directory=str(DEMO_ROOT / "scratch"), content={0: "cli"}),
        ],
    ),
    Window(
        key="w2",
        frame={"x": 1560, "y": 200, "width": 1100, "height": 760},
        active_tab=0,
        tabs=[
            Tab(key="w2t1", directory=str(REPOS / "web-ui"), content={0: "tree"}),
            Tab(key="w2t2", directory=str(REPOS / "infra"), content={0: "build"}),
        ],
    ),
]

# Hand-picked colors that beat the identity hash, keyed by repo identity,
# which is the absolute repo path plus the worktree name when there is one.
REPO_OVERRIDES = {str(REPOS / "infra"): ["brightMagenta"]}


def _leaf(tab_key: str, index: int) -> dict:
    return {
        "type": "leaf",
        "leaf": {
            "id": demo_uuid(f"{tab_key}.leaf{index}"),
            "surfaceID": demo_uuid(f"{tab_key}.surface{index}"),
        },
    }


def _layout(tab: Tab) -> dict:
    """One, two, or three panes. Three is a wide left pane beside a stacked pair."""
    if tab.panes == 1:
        return _leaf(tab.key, 0)
    if tab.panes == 2:
        return {
            "type": "split",
            "branch": {
                "id": demo_uuid(f"{tab.key}.branch"),
                "orientation": "horizontal",
                "ratio": 0.5,
                "first": _leaf(tab.key, 0),
                "second": _leaf(tab.key, 1),
            },
        }
    return {
        "type": "split",
        "branch": {
            "id": demo_uuid(f"{tab.key}.branch"),
            "orientation": "horizontal",
            "ratio": 0.62,
            "first": _leaf(tab.key, 0),
            "second": {
                "type": "split",
                "branch": {
                    "id": demo_uuid(f"{tab.key}.branch2"),
                    "orientation": "vertical",
                    "ratio": 0.5,
                    "first": _leaf(tab.key, 1),
                    "second": _leaf(tab.key, 2),
                },
            },
        },
    }


def _tab_json(tab: Tab, position: int) -> dict:
    leaf_directories: list[str] = []
    for index in range(tab.panes):
        leaf_directories.append(demo_uuid(f"{tab.key}.leaf{index}"))
        leaf_directories.append(tab.directory)
    out = {
        "tabID": demo_uuid(f"{tab.key}.tab"),
        "name": tab.name,
        "position": position,
        "focusedLeafID": demo_uuid(f"{tab.key}.leaf{tab.focused_pane}"),
        "splitLayout": _layout(tab),
        "leafDirectories": leaf_directories,
        "leafColorOverrides": [],
    }
    if tab.color:
        out["colorOverride"] = tab.color if len(tab.color) > 1 else tab.color[0]
    return out


def build_session() -> dict:
    windows = []
    for window in WINDOWS:
        tabs = [_tab_json(tab, i) for i, tab in enumerate(window.tabs)]
        windows.append(
            {
                "windowID": demo_uuid(f"{window.key}.window"),
                "frame": window.frame,
                "sidebarWidth": 200,
                "activeTabID": tabs[window.active_tab]["tabID"],
                "tabs": tabs,
            }
        )
    return {
        "version": 4,
        "surfaceTintEnabled": True,
        "keyWindowID": windows[0]["windowID"],
        "repoColorOverrides": {
            path: stops if len(stops) > 1 else stops[0]
            for path, stops in REPO_OVERRIDES.items()
        },
        "windows": windows,
    }


if __name__ == "__main__":
    print(json.dumps(build_session(), indent=2))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test_montty_demo.py`
Expected: PASS, 10 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/montty_demo.py scripts/test_montty_demo.py
git commit -m "feat: generate a deterministic demo session for screenshots"
```

---

### Task 2: Demo world materialization

**Files:**
- Modify: `scripts/montty_demo.py`
- Test: `scripts/test_montty_demo.py`

**Interfaces:**
- Consumes: `DEMO_ROOT`, `REPOS`, `WINDOWS`, `build_session` from Task 1.
- Produces: `PANE_FIXTURES: dict[str, str]`, `materialize_world(root: Path = DEMO_ROOT) -> None`, `GHOSTTY_CONFIG: str`, `ZSHRC: str`.

- [ ] **Step 1: Write the failing test**

Append to `scripts/test_montty_demo.py`, above the `__main__` block:

```python
import tempfile


class MaterializeWorldTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        demo.materialize_world(self.root)

    def test_writes_a_branch_ref_a_git_directory_walk_can_read(self):
        head = self.root / "repos" / "acme-api" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/main")

    def test_web_ui_carries_a_different_branch(self):
        head = self.root / "repos" / "web-ui" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/feature/checkout")

    def test_hotfix_is_a_worktree_pointing_at_its_parent(self):
        git_file = self.root / "repos" / "acme-api-hotfix" / ".git"
        self.assertTrue(git_file.is_file())
        self.assertIn("gitdir:", git_file.read_text())
        self.assertIn("acme-api", git_file.read_text())

    def test_scratch_has_no_git_so_it_renders_gray(self):
        self.assertTrue((self.root / "scratch").is_dir())
        self.assertFalse((self.root / "scratch" / ".git").exists())

    def test_pins_the_palette_so_colors_do_not_follow_the_users_theme(self):
        config = (self.root / "config" / "ghostty" / "config").read_text()
        self.assertIn("palette = 2=#a6e3a1", config)
        self.assertIn("command = /bin/zsh", config)

    def test_zshrc_sets_a_prompt_that_names_no_user(self):
        zshrc = (self.root / "zdotdir" / ".zshrc").read_text()
        self.assertIn("PROMPT=", zshrc)
        self.assertNotIn(str(Path.home()), zshrc)

    def test_writes_every_pane_fixture_the_roster_references(self):
        referenced = {
            name
            for window in demo.WINDOWS
            for tab in window.tabs
            for name in tab.content.values()
        }
        for name in referenced:
            self.assertTrue((self.root / "fixtures" / f"{name}.txt").is_file(), name)

    def test_is_idempotent(self):
        demo.materialize_world(self.root)
        head = self.root / "repos" / "acme-api" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/main")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 scripts/test_montty_demo.py`
Expected: FAIL with `AttributeError: module 'montty_demo' has no attribute 'materialize_world'`

- [ ] **Step 3: Write minimal implementation**

Add to `scripts/montty_demo.py`, above the `__main__` block. The palette is Catppuccin Mocha written out explicitly rather than named as a theme, so the demo does not depend on which theme files ship inside GhosttyKit:

```python
BRANCHES = {
    "acme-api": "main",
    "web-ui": "feature/checkout",
    "infra": "main",
}

GHOSTTY_CONFIG = """\
palette = 0=#45475a
palette = 1=#f38ba8
palette = 2=#a6e3a1
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#cba6f7
palette = 6=#94e2d5
palette = 7=#bac2de
palette = 8=#585b70
palette = 9=#eba0ac
palette = 10=#a6e3a1
palette = 11=#f9e2af
palette = 12=#89dceb
palette = 13=#f5c2e7
palette = 14=#94e2d5
palette = 15=#a6adc8
background = #1e1e2e
foreground = #cdd6f4
font-size = 13
window-padding-x = 8
window-padding-y = 6
command = /bin/zsh
"""

# A login shell would print "Last login: ..." and date every screenshot, which
# is why the config above runs a plain interactive zsh instead.
ZSHRC = """\
HISTFILE=""
setopt PROMPT_SUBST
PROMPT='%F{blue}%1~%f %F{green}> %f'
export PAGER=cat
"""

PANE_FIXTURES = {
    "tree": """\
Cargo.toml    README.md     src/          tests/
""",
    "build": """\
   Compiling acme-api v0.4.3
    Finished release [optimized] in 12.4s
     Running target/release/acme-api
listening on 0.0.0.0:8080
""",
    "tests": """\
running 24 tests
........................
test result: ok. 24 passed; 0 failed
""",
    "cli": "",
}


def materialize_world(root: Path = DEMO_ROOT) -> None:
    """Create the demo tree. Safe to rerun over an existing tree."""
    for name, branch in BRANCHES.items():
        git_dir = root / "repos" / name / ".git"
        git_dir.mkdir(parents=True, exist_ok=True)
        (git_dir / "HEAD").write_text(f"ref: refs/heads/{branch}\n")

    # A linked worktree is a .git file, which is what makes montty render the
    # parent repo's leading stop with the worktree's own trailing stop.
    hotfix = root / "repos" / "acme-api-hotfix"
    hotfix.mkdir(parents=True, exist_ok=True)
    (hotfix / ".git").write_text(
        f"gitdir: {root / 'repos' / 'acme-api' / '.git'}/worktrees/acme-api-hotfix\n"
    )
    worktree_meta = root / "repos" / "acme-api" / ".git" / "worktrees" / "acme-api-hotfix"
    worktree_meta.mkdir(parents=True, exist_ok=True)
    (worktree_meta / "HEAD").write_text("ref: refs/heads/hotfix/token-expiry\n")

    (root / "scratch").mkdir(parents=True, exist_ok=True)

    config = root / "config" / "ghostty"
    config.mkdir(parents=True, exist_ok=True)
    (config / "config").write_text(GHOSTTY_CONFIG)

    zdotdir = root / "zdotdir"
    zdotdir.mkdir(parents=True, exist_ok=True)
    (zdotdir / ".zshrc").write_text(ZSHRC)

    fixtures = root / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    for name, body in PANE_FIXTURES.items():
        (fixtures / f"{name}.txt").write_text(body)

    session = root / "session"
    session.mkdir(parents=True, exist_ok=True)
    (session / "session.json").write_text(json.dumps(build_session(), indent=2))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 scripts/test_montty_demo.py`
Expected: PASS, 18 tests

- [ ] **Step 5: Commit**

```bash
git add scripts/montty_demo.py scripts/test_montty_demo.py
git commit -m "feat: materialize the montty demo tree from fixtures"
```

---

### Task 3: Launch and report, the review gate

**Files:**
- Modify: `scripts/montty_demo.py`
- Modify: `justfile`

**Interfaces:**
- Consumes: `materialize_world`, `DEMO_ROOT` from Task 2.
- Produces: `BUILD_DIR: Path`, `SERVER: str`, `launch() -> None`, `stop() -> None`, `wait_for_server(timeout: float = 20.0) -> list[dict]`, `get(path: str) -> list | dict`, `report() -> None`, `main()` with subcommands.

- [ ] **Step 1: Add the launch, wait, and report functions**

Add to `scripts/montty_demo.py`. Everything here talks to the debug server over stdlib HTTP, so the script keeps no dependency beyond Pillow, which later tasks import lazily:

```python
import os
import subprocess
import sys
import time
import urllib.request

BUILD_DIR = Path("/tmp/montty-build")
APP = BUILD_DIR / "Debug" / "Montty.app" / "Contents" / "MacOS" / "Montty"
SERVER = "http://localhost:9876"


def demo_env() -> dict[str, str]:
    """The four variables that make a run hermetic. HOME is deliberately absent:
    Claude Code's login lives there, and a fresh HOME logs the demo pane out."""
    env = dict(os.environ)
    env["XDG_CONFIG_HOME"] = str(DEMO_ROOT / "config")
    env["ZDOTDIR"] = str(DEMO_ROOT / "zdotdir")
    env["MONTTY_SESSION_DIR"] = str(DEMO_ROOT / "session")
    env["MONTTY_SOCKET"] = str(DEMO_ROOT / "hook.sock")
    return env


def get(path: str):
    with urllib.request.urlopen(f"{SERVER}{path}", timeout=5) as response:
        return json.loads(response.read())


def stop() -> None:
    subprocess.run(["just", "stop"], check=False, capture_output=True)
    time.sleep(1)


def launch() -> None:
    subprocess.Popen([str(APP)], env=demo_env(), start_new_session=True)


def wait_for_server(timeout: float = 20.0) -> list[dict]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            return get("/surfaces")
        except Exception:
            time.sleep(0.5)
    raise SystemExit("montty debug server never answered on :9876")


def report() -> None:
    """Print what montty actually resolved, so the roster and palette can be
    judged against the running window rather than against the spec."""
    surfaces = get("/surfaces")
    seen: set[str] = set()
    print(f"{'tab':<22}{'branch':<24}{'source':<9}color")
    for surface in surfaces:
        tab = surface.get("tab_id", "")
        if tab in seen:
            continue
        seen.add(tab)
        color = surface.get("color", {})
        git = surface.get("git") or {}
        print(
            f"{surface.get('tab_name', ''):<22}"
            f"{git.get('branch', '-'):<24}"
            f"{color.get('source', '-'):<9}"
            f"{','.join(color.get('effective', []))}"
        )
```

- [ ] **Step 2: Add the subcommand dispatcher**

Replace the `__main__` block at the bottom of `scripts/montty_demo.py`:

```python
def cmd_build() -> None:
    subprocess.run(["just", "build"], check=True)
    stop()
    materialize_world()
    launch()
    wait_for_server()
    report()


def main() -> None:
    commands = {"build": cmd_build, "session": lambda: print(json.dumps(build_session(), indent=2))}
    name = sys.argv[1] if len(sys.argv) > 1 else "build"
    if name not in commands:
        raise SystemExit(f"unknown command {name!r}; try {', '.join(commands)}")
    commands[name]()


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Add the just recipe**

Add to `justfile` after the `inspect-quit` recipe:

```makefile
# Build the demo world and open montty on it, for judging the screenshot layout
demo:
    @uv run scripts/montty_demo.py build
```

- [ ] **Step 4: Run it**

Run: `just demo`
Expected: montty opens two windows on the demo session, and the terminal prints one row per tab naming the branch, the color source, and the resolved stops. Six rows for window one and two for window two.

- [ ] **Step 5: Verify the isolation actually held**

Check each of these against the running window, because each is a way the demo can leak or drift:

- The prompt in every pane is the demo prompt, not the personal one. If Ghostty's zsh shell integration has overridden `ZDOTDIR`, the fallback is to add `shell-integration-features = no-cursor` to `GHOSTTY_CONFIG` and re-run, keeping integration on so directory reporting survives.
- The sidebar shows a git branch under each repo tab. If it does not, `pwd` reporting is not reaching montty and shell integration is off, which the same fallback addresses.
- No pane shows `Last login:` and no path in frame contains the real username.
- The `acme-api-hotfix` tab shows a worktree label and a gradient that leads with the parent repo's stop.
- The `infra` tab renders `brightMagenta`, proving the repo override beat the hash.

- [ ] **Step 6: Commit**

```bash
git add scripts/montty_demo.py justfile
git commit -m "feat: open montty on the demo world for layout review"
```

- [ ] **Step 7: STOP. Hand the window to Ted.**

Do not begin Task 4. Show the printed table, say the window is open, and ask which directories, names, or colors to change. Apply tweaks by editing `WINDOWS` and `REPO_OVERRIDES` in `scripts/montty_demo.py`, re-running `just demo`, and committing the adjusted roster. Only move on once Ted says the layout is settled.

---

## Phase 2: automation

### Task 4: Verify the restored layout matches the roster

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `WINDOWS`, `get`, `demo_uuid` from Tasks 1 and 3.
- Produces: `verify_layout() -> None`.

- [ ] **Step 1: Add the verification**

```python
def verify_layout() -> None:
    """Fail loudly when the restored layout is not the one the roster asked for.
    A session schema change should surface here, not as a wrong screenshot."""
    surfaces = get("/surfaces")
    problems: list[str] = []

    expected_panes = sum(tab.panes for window in WINDOWS for tab in window.tabs)
    if len(surfaces) != expected_panes:
        problems.append(f"expected {expected_panes} panes, montty restored {len(surfaces)}")

    expected_windows = len({s["window_id"] for s in surfaces})
    if expected_windows != len(WINDOWS):
        problems.append(f"expected {len(WINDOWS)} windows, montty restored {expected_windows}")

    by_tab = {s["tab_id"]: s for s in surfaces}
    for window in WINDOWS:
        for tab in window.tabs:
            tab_id = demo_uuid(f"{tab.key}.tab")
            surface = by_tab.get(tab_id)
            if surface is None:
                problems.append(f"tab {tab.key} did not restore")
                continue
            if tab.name and surface.get("tab_name") != tab.name:
                problems.append(
                    f"tab {tab.key} is named {surface.get('tab_name')!r}, expected {tab.name!r}"
                )
            if surface.get("split_count") != tab.panes:
                problems.append(
                    f"tab {tab.key} has {surface.get('split_count')} panes, expected {tab.panes}"
                )

    if problems:
        raise SystemExit("demo layout did not restore as specified:\n  " + "\n  ".join(problems))
```

- [ ] **Step 2: Call it from `cmd_build`**

Insert `verify_layout()` between `wait_for_server()` and `report()` in `cmd_build`.

- [ ] **Step 3: Run it**

Run: `just demo`
Expected: same table as before, no verification error.

- [ ] **Step 4: Prove the gate bites**

Temporarily change `panes=3` to `panes=2` on the `w1t2` tab, run `just demo`, and confirm it exits with `tab w1t2 has 3 panes, expected 2`. Revert the change.

- [ ] **Step 5: Commit**

```bash
git add scripts/montty_demo.py
git commit -m "feat: fail loudly when the demo layout does not restore as specified"
```

---

### Task 5: Fill panes with fixture content

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `WINDOWS`, `get`, `demo_uuid`, `PANE_FIXTURES` from earlier tasks.
- Produces: `post(path: str, body: str) -> None`, `surface_for(tab_key: str, pane: int, surfaces: list[dict]) -> dict`, `fill_panes() -> None`.

- [ ] **Step 1: Add the driving helpers**

```python
def post(path: str, body: str = "") -> None:
    request = urllib.request.Request(
        f"{SERVER}{path}", data=body.encode(), method="POST"
    )
    with urllib.request.urlopen(request, timeout=10):
        pass


def surface_for(tab_key: str, pane: int, surfaces: list[dict]) -> dict:
    """Resolve a roster pane to a live surface through its stable leaf id."""
    leaf_id = demo_uuid(f"{tab_key}.leaf{pane}")
    for surface in surfaces:
        if surface.get("leaf_id") == leaf_id:
            return surface
    raise SystemExit(f"no live surface for {tab_key} pane {pane}")


def run_in(surface: dict, command: str) -> None:
    target = surface["id"]
    post(f"/type?surface={target}", command)
    post(f"/key?surface={target}", "return")


def fill_panes() -> None:
    """Clear each pane, then cat its fixture, so output is identical every run
    and no login banner survives above it."""
    surfaces = get("/surfaces")
    for window in WINDOWS:
        for tab in window.tabs:
            for pane, fixture in tab.content.items():
                surface = surface_for(tab.key, pane, surfaces)
                run_in(surface, "clear")
                if fixture == "cli":
                    run_in(surface, "montty --help")
                else:
                    run_in(surface, f"cat {DEMO_ROOT}/fixtures/{fixture}.txt")
    time.sleep(1.5)
```

- [ ] **Step 2: Call it from `cmd_build`**

Insert `fill_panes()` after `verify_layout()` in `cmd_build`.

- [ ] **Step 3: Run it**

Run: `just demo`
Expected: every pane shows its fixture text with no `Last login` line above it, and the `scratch/` tab shows the `montty --help` palette swatches in color.

- [ ] **Step 4: Commit**

```bash
git add scripts/montty_demo.py
git commit -m "feat: fill demo panes from fixtures over the debug server"
```

---

### Task 6: Light the activity indicators through the real CLI

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `WINDOWS`, `surface_for`, `get`, `demo_env`, `APP` from earlier tasks.
- Produces: `set_statuses() -> None`.

- [ ] **Step 1: Add the status driver**

The CLI needs only `MONTTY_SURFACE_ID` and `MONTTY_SOCKET` in the environment, which is what lets a script outside a pane drive it. The binary is `APP` from Task 3: the same executable serves the GUI and the CLI, deciding by argv.

```python
def set_statuses() -> None:
    surfaces = get("/surfaces")
    for window in WINDOWS:
        for tab in window.tabs:
            for pane, status in tab.statuses.items():
                surface = surface_for(tab.key, pane, surfaces)
                env = demo_env()
                env["MONTTY_SURFACE_ID"] = surface["montty_surface_id"]
                result = subprocess.run(
                    [str(APP), "surface", "status", status],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                if result.returncode != 0:
                    raise SystemExit(
                        f"montty surface status {status} failed: {result.stderr.strip()}"
                    )
```

- [ ] **Step 2: Call it from `cmd_build`**

Insert `set_statuses()` after `fill_panes()` in `cmd_build`.

- [ ] **Step 3: Run it**

Run: `just demo`, then `just inspect-claude-states`
Expected: two entries, one `working` and one `waiting`, and the minimap panes in the `MR !123 fix auth` tab carry their indicators.

- [ ] **Step 4: Commit**

```bash
git add scripts/montty_demo.py
git commit -m "feat: drive demo activity indicators through the montty CLI"
```

---

### Task 7: The live Claude pane

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `WINDOWS`, `surface_for`, `run_in`, `post`, `get` from earlier tasks.
- Produces: `CLAUDE_PROMPTS: list[str]`, `start_claude() -> None`.

- [ ] **Step 1: Add the Claude driver**

Two exchanges, because one is not enough to push the startup banner, with its model and plan tier, out of the viewport:

```python
CLAUDE_PROMPTS = [
    "in one sentence, what does this service do?",
    "which file would I edit to change the listen port?",
]


def start_claude(settle: float = 45.0) -> None:
    surfaces = get("/surfaces")
    for window in WINDOWS:
        for tab in window.tabs:
            if tab.claude_pane is None:
                continue
            surface = surface_for(tab.key, tab.claude_pane, surfaces)
            run_in(surface, "clear")
            run_in(surface, "claude")
            time.sleep(8)
            # A directory Claude has not seen asks to be trusted first.
            post(f"/key?surface={surface['id']}", "return")
            time.sleep(2)
            for prompt in CLAUDE_PROMPTS:
                post(f"/type?surface={surface['id']}", prompt)
                post(f"/key?surface={surface['id']}", "return")
                time.sleep(settle / len(CLAUDE_PROMPTS))
```

- [ ] **Step 2: Call it from a new full-run command**

Add `cmd_shoot`, which is the full pipeline, and leave `cmd_build` as the fast layout loop:

```python
def cmd_shoot() -> None:
    cmd_build()
    start_claude()
    capture_all()
```

Register both in `main`'s `commands` dict as `"build"` and `"shoot"`.

- [ ] **Step 3: Run it**

Run: `uv run scripts/montty_demo.py shoot` (it will fail at `capture_all`, which Task 8 adds)
Expected: the focused pane holds a real Claude conversation with the startup banner scrolled out of view. If the banner is still visible, raise `settle` or add a third prompt.

- [ ] **Step 4: Commit**

```bash
git add scripts/montty_demo.py
git commit -m "feat: run a live Claude exchange in the demo hero pane"
```

---

### Task 8: Capture the four images in a safe order

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `WINDOWS`, `surface_for`, `post`, `SERVER` from earlier tasks.
- Produces: `DOCS: Path`, `capture(surface_id: str, path: Path) -> None`, `capture_all() -> None`.

- [ ] **Step 1: Add the capture functions**

Order matters because each step mutates what the next would see:

```python
DOCS = Path(__file__).resolve().parent.parent / "docs"
RAW = DEMO_ROOT / "raw"


def capture(surface_id: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(f"{SERVER}/screenshot?surface={surface_id}", timeout=20) as r:
        path.write_bytes(r.read())
    time.sleep(0.5)


def capture_all() -> None:
    surfaces = get("/surfaces")
    hero = surface_for("w1t2", 0, surfaces)
    second_window = surface_for("w2t1", 0, surfaces)
    cli = surface_for("w1t6", 0, surfaces)

    # Hero first: it needs the focused tab untouched and jump mode inactive.
    capture(hero["id"], RAW / "hero.png")

    post("/jump", "")
    time.sleep(0.5)
    capture(hero["id"], RAW / "jump.png")
    post(f"/key?surface={hero['id']}", "escape")
    time.sleep(0.5)

    # Each window is captured on its own; they are composited in Task 9.
    capture(hero["id"], RAW / "window-one.png")
    capture(second_window["id"], RAW / "window-two.png")

    # Last, because switching tabs moves the focus.
    post("/action?surface=" + cli["id"], "goto_tab:6")
    time.sleep(1)
    capture(cli["id"], RAW / "cli.png")
```

- [ ] **Step 2: Run it**

Run: `uv run scripts/montty_demo.py shoot`
Expected: five PNGs under `/private/tmp/montty-demo/raw/`. Open them and confirm the jump image carries labels and the hero image does not.

- [ ] **Step 3: Commit**

```bash
git add scripts/montty_demo.py
git commit -m "feat: capture the demo windows in a mutation-safe order"
```

---

### Task 9: Composite and downscale into docs

**Files:**
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `RAW`, `DOCS` from Task 8.
- Produces: `postprocess() -> None`.

- [ ] **Step 1: Add the post-processing**

Pillow is imported inside the function so the stdlib-only tests keep running without it:

```python
TARGET_WIDTH = 1400
BACKDROP = (30, 30, 46)


def _downscale(image, width: int = TARGET_WIDTH):
    from PIL import Image

    if image.width <= width:
        return image
    height = round(image.height * width / image.width)
    return image.resize((width, height), Image.LANCZOS)


def postprocess() -> None:
    from PIL import Image

    for source, target in [
        ("hero.png", "screenshot.png"),
        ("jump.png", "screenshot-easymotion.png"),
        ("cli.png", "screenshot-cli.png"),
    ]:
        image = Image.open(RAW / source)
        _downscale(image).save(DOCS / target, optimize=True)

    # Two genuine window captures placed side by side, which avoids the Screen
    # Recording permission a real two-window screen grab would need.
    one = Image.open(RAW / "window-one.png")
    two = Image.open(RAW / "window-two.png")
    gap = 40
    canvas = Image.new(
        "RGB", (one.width + two.width + gap * 3, max(one.height, two.height) + gap * 2), BACKDROP
    )
    canvas.paste(one, (gap, gap))
    canvas.paste(two, (gap * 2 + one.width, gap))
    _downscale(canvas, 1600).save(DOCS / "screenshot-windows.png", optimize=True)
```

- [ ] **Step 2: Call it from `cmd_shoot`**

Append `postprocess()` then `stop()` to `cmd_shoot`, after `capture_all()`, so a full run leaves no demo montty behind. The demo tree stays for inspection; `just screenshots-clean` removes it.

- [ ] **Step 3: Run it**

Run: `uv run scripts/montty_demo.py shoot`
Expected: four PNGs in `docs/`, each about 1400px wide, each well under the 600KB the current pair weigh. Check with `ls -la docs/*.png`.

- [ ] **Step 4: Commit**

```bash
git add scripts/montty_demo.py docs/screenshot.png docs/screenshot-easymotion.png docs/screenshot-windows.png docs/screenshot-cli.png
git commit -m "feat: composite and downscale the demo captures into docs"
```

---

### Task 10: The remaining recipes

**Files:**
- Modify: `justfile`
- Modify: `scripts/montty_demo.py`

**Interfaces:**
- Consumes: `cmd_build`, `cmd_shoot`, `DEMO_ROOT`.
- Produces: `cmd_preview()`, `cmd_clean()`.

- [ ] **Step 1: Add the preview and clean commands**

```python
def cmd_preview() -> None:
    """The palette loop: relaunch on the current roster and shoot only the hero,
    skipping the Claude exchange, so trying a color costs seconds and no tokens."""
    cmd_build()
    surfaces = get("/surfaces")
    capture(surface_for("w1t2", 0, surfaces)["id"], RAW / "hero.png")
    from PIL import Image

    _downscale(Image.open(RAW / "hero.png")).save(DOCS / "screenshot.png", optimize=True)
    print(f"wrote {DOCS / 'screenshot.png'}")


def cmd_clean() -> None:
    import shutil

    stop()
    shutil.rmtree(DEMO_ROOT, ignore_errors=True)
    print(f"removed {DEMO_ROOT}")
```

Register both in `main`'s `commands` dict as `"preview"` and `"clean"`.

- [ ] **Step 2: Add the recipes**

```makefile
# Regenerate every README screenshot from the demo world
screenshots:
    @uv run scripts/montty_demo.py shoot

# Reshoot only the hero image, skipping the Claude session, for palette tuning
screenshots-preview:
    @uv run scripts/montty_demo.py preview

# Remove the demo world
screenshots-clean:
    @uv run scripts/montty_demo.py clean
```

- [ ] **Step 3: Run each**

Run: `just screenshots-preview`, then `just screenshots-clean`, then `just screenshots`
Expected: preview rewrites only the hero, clean removes `/private/tmp/montty-demo`, and the full run rebuilds the tree and all four images from scratch.

- [ ] **Step 4: Commit**

```bash
git add justfile scripts/montty_demo.py
git commit -m "feat: add screenshot, preview, and clean recipes"
```

---

### Task 11: README images and prose

**Files:**
- Modify: `README.md`
- Modify: `docs/debug-server.md`

- [ ] **Step 1: Swap and caption the images**

Keep the hero at the top. Place the jump image where the easy-motion one is now. Add the two-window image beside the new multiple-windows prose, and the CLI image beside the CLI prose.

- [ ] **Step 2: Correct the feature list**

The current list predates four features. Add, in the existing voice and without emoji or em-dashes:

- Multiple windows from one process, opened with `Cmd-N`, each owning its own tabs, which never move between windows.
- The `montty` CLI for setting colors, names, and activity status from a shell or a script, linking `docs/montty-cli.md`.
- Colors resolving surface, then tab, then repo, then the automatic git signature, with repo colors shared across every tab in a repo.
- Gradient tints of up to three stops, and what a worktree's gradient means.
- Opening the focused pane's directory in an editor.

- [ ] **Step 3: Document the harness**

Add a short section to `docs/debug-server.md` naming `just screenshots`, `just screenshots-preview`, `just demo`, and `just screenshots-clean`, and pointing at the roster in `scripts/montty_demo.py` as the place to change what the images show.

- [ ] **Step 4: Check every claim against the images**

Read the README top to bottom with the four new images open. Every feature the prose names must be either visible in an image or plainly described. Remove any claim the current build does not support.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/debug-server.md
git commit -m "docs: refresh README images and cover the features added since March"
```
