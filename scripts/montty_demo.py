#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow"]
# ///
# ABOUTME: Builds the montty demo world, seeds a session, and drives the app to
# ABOUTME: regenerate every screenshot the README uses.
from __future__ import annotations
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


if __name__ == "__main__":
    print(json.dumps(build_session(), indent=2))
