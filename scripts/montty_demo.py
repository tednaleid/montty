#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
# ABOUTME: Builds the montty demo world, seeds a session, and drives the app to
# ABOUTME: regenerate every screenshot the README uses.
from __future__ import annotations
import json
import os
import subprocess
import sys
import time
import urllib.request
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
            Tab(key="w1t1", directory=str(REPOS / "payments"), content={0: "tree"}),
            Tab(
                key="w1t2",
                directory=str(REPOS / "payments"),
                name="MR !123 fix auth",
                color=["neutralBright", "green"],
                panes=3,
                focused_pane=0,
                statuses={1: "working", 2: "waiting"},
                claude_pane=0,
                content={1: "build", 2: "tests"},
            ),
            Tab(key="w1t3", directory=str(REPOS / "orders"), panes=2, content={0: "tree", 1: "build"}),
            Tab(key="w1t4", directory=str(REPOS / "payments-release"), content={0: "tree"}),
            Tab(key="w1t5", directory=str(REPOS / "dashboard"), content={0: "tree"}),
            Tab(key="w1t6", directory=str(DEMO_ROOT / "scratch"), content={0: "cli"}),
        ],
    ),
    Window(
        key="w2",
        frame={"x": 1560, "y": 200, "width": 1100, "height": 760},
        active_tab=0,
        tabs=[
            Tab(key="w2t1", directory=str(REPOS / "orders"), content={0: "tree"}),
            Tab(key="w2t2", directory=str(REPOS / "dashboard"), content={0: "build"}),
        ],
    ),
]

# Hand-picked colors that beat the identity hash, keyed by repo identity,
# which is the absolute repo path plus the worktree name when there is one.
REPO_OVERRIDES = {str(REPOS / "dashboard"): ["magenta"]}


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
                "sidebarWidth": 260,
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


BRANCHES = {
    "payments": "main",
    "orders": "feature/split-tender",
    "dashboard": "main",
}

GHOSTTY_CONFIG = """\
palette = 0=#000000
palette = 1=#f2777a
palette = 2=#99cc99
palette = 3=#ffcc66
palette = 4=#6699cc
palette = 5=#cc99cc
palette = 6=#66cccc
palette = 7=#ffffff
palette = 8=#595959
palette = 9=#f2777a
palette = 10=#99cc99
palette = 11=#ffcc66
palette = 12=#6699cc
palette = 13=#cc99cc
palette = 14=#66cccc
palette = 15=#ffffff
background = #2d2d2d
foreground = #cccccc
cursor-color = #cccccc
font-family = "Fira Code"
font-size = 15
window-padding-x = 10
window-padding-y = 10
command = /bin/zsh
"""

# Ghostty always execs macOS panes through /usr/bin/login, so Last login:
# is unavoidable here; only a .hushlogin in the real home (not written by
# this harness) suppresses it. command = /bin/zsh just pins the shell choice.
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
   Compiling payments v0.4.3
    Finished release [optimized] in 12.4s
     Running target/release/payments
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
    hotfix = root / "repos" / "payments-release"
    hotfix.mkdir(parents=True, exist_ok=True)
    (hotfix / ".git").write_text(
        f"gitdir: {root / 'repos' / 'payments' / '.git'}/worktrees/payments-release\n"
    )
    worktree_meta = root / "repos" / "payments" / ".git" / "worktrees" / "payments-release"
    worktree_meta.mkdir(parents=True, exist_ok=True)
    (worktree_meta / "HEAD").write_text("ref: refs/heads/release/2.4\n")

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
    # Detached stdio: an inherited pipe keeps `just demo | tail` open until
    # montty exits, which is never, since the app is meant to stay up.
    log = open(DEMO_ROOT / "montty.log", "ab")
    subprocess.Popen(
        [str(APP)], env=demo_env(), start_new_session=True,
        stdin=subprocess.DEVNULL, stdout=log, stderr=log,
    )


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
