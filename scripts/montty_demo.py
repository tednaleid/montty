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

DEMO_ROOT = Path("/tmp/montty-demo")
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
