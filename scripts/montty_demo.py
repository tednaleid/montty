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
import shutil
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
                color=["green", "neutralBright"],
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
palette = 1=#b30d0e
palette = 2=#00bb00
palette = 3=#fecd22
palette = 4=#3a9bdb
palette = 5=#bb00bb
palette = 6=#00bbbb
palette = 7=#bbbbbb
palette = 8=#555555
palette = 9=#ff0003
palette = 10=#93c863
palette = 11=#fef874
palette = 12=#a1d7ff
palette = 13=#ff55ff
palette = 14=#55ffff
palette = 15=#ffffff
background = #283033
foreground = #cdcdcd
cursor-color = #c0cad0
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
export PATH="/opt/homebrew/bin:$PATH"
"""

# The only fixture repo the live Claude pane actually explores, so it needs a
# real source tree; the other repos' fixtures only ever appear via a static
# `cat` and stay as bare .git directories.
PAYMENTS_SOURCE = {
    "Cargo.toml": """\
[package]
name = "payments"
version = "0.4.3"
edition = "2021"

[dependencies]
axum = "0.7"
tokio = { version = "1", features = ["full"] }
""",
    "README.md": """\
# payments

Handles payment authorization and capture for the checkout flow.
""",
    "src/main.rs": """\
use axum::Router;

#[tokio::main]
async fn main() {
    let app = Router::new();
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
""",
}

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
    payments_release = root / "repos" / "payments-release"
    payments_release.mkdir(parents=True, exist_ok=True)
    (payments_release / ".git").write_text(
        f"gitdir: {root / 'repos' / 'payments' / '.git'}/worktrees/payments-release\n"
    )
    worktree_meta = root / "repos" / "payments" / ".git" / "worktrees" / "payments-release"
    worktree_meta.mkdir(parents=True, exist_ok=True)
    (worktree_meta / "HEAD").write_text("ref: refs/heads/release/2.4\n")

    for relative_path, body in PAYMENTS_SOURCE.items():
        source_file = root / "repos" / "payments" / relative_path
        source_file.parent.mkdir(parents=True, exist_ok=True)
        source_file.write_text(body)

    (root / "scratch").mkdir(parents=True, exist_ok=True)

    config = root / "config" / "ghostty"
    config.mkdir(parents=True, exist_ok=True)
    (config / "config").write_text(GHOSTTY_CONFIG)

    # veer also reads XDG_CONFIG_HOME for its own global config, so without
    # this it searches the demo's config tree, finds no rules, and fails
    # every tool call closed as a safety default.
    veer_config = root / "config" / "veer"
    veer_config.mkdir(parents=True, exist_ok=True)
    (veer_config / "config.toml").write_text("")

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
    """Inherits the caller's environment, overrides what needs to be hermetic,
    and strips markers a parent Claude Code session would otherwise leak into
    the demo's own Claude pane. HOME is deliberately left alone: Claude Code's
    login lives there, and a fresh HOME logs the demo pane out."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_CODE_")}
    env["XDG_CONFIG_HOME"] = str(DEMO_ROOT / "config")
    env["ZDOTDIR"] = str(DEMO_ROOT / "zdotdir")
    env["MONTTY_SESSION_DIR"] = str(DEMO_ROOT / "session")
    env["MONTTY_SOCKET"] = str(DEMO_ROOT / "hook.sock")
    # Claude Code otherwise announces a finished background update across the
    # transcript, which lands in the hero shot.
    env["DISABLE_AUTOUPDATER"] = "1"
    return env


def get(path: str):
    with urllib.request.urlopen(f"{SERVER}{path}", timeout=5) as response:
        return json.loads(response.read())


def stop() -> None:
    subprocess.run(["just", "stop"], check=False, capture_output=True)
    deadline = time.time() + 10.0
    while time.time() < deadline:
        try:
            get("/surfaces")
            time.sleep(0.2)
        except Exception:
            return
    # The debug server never went quiet. Proceed anyway: launch() or
    # wait_for_server() will surface whatever is actually wrong next.


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


def verify_layout() -> None:
    """Fail loudly when the restored layout is not the one the roster asked for.
    A session schema change should surface here, not as a wrong screenshot."""
    surfaces = get("/surfaces")
    problems: list[str] = []

    expected_panes = sum(tab.panes for window in WINDOWS for tab in window.tabs)
    if len(surfaces) != expected_panes:
        problems.append(f"expected {expected_panes} panes, montty restored {len(surfaces)}")

    observed_windows = len({s["window_id"] for s in surfaces})
    if observed_windows != len(WINDOWS):
        problems.append(f"expected {len(WINDOWS)} windows, montty restored {observed_windows}")

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
            if tab.color:
                color = surface.get("color", {})
                if color.get("source") != "tab" or color.get("effective") != tab.color:
                    problems.append(
                        f"tab {tab.key} resolved {color.get('source')}/"
                        f"{color.get('effective')}, expected tab/{tab.color}"
                    )

    # A repo override resolves through an identity hash of the repo path, which
    # falls back silently when the key stops matching, so assert it landed.
    for repo_path, stops in REPO_OVERRIDES.items():
        covered = False
        for window in WINDOWS:
            for tab in window.tabs:
                in_repo = tab.directory == repo_path or tab.directory.startswith(repo_path + "/")
                if tab.color or not in_repo:
                    continue
                surface = by_tab.get(demo_uuid(f"{tab.key}.tab"))
                if surface is None:
                    continue
                covered = True
                color = surface.get("color", {})
                if color.get("source") != "repo" or color.get("effective") != stops:
                    problems.append(
                        f"tab {tab.key} resolved {color.get('source')}/"
                        f"{color.get('effective')}, expected repo/{stops}"
                    )
        if not covered:
            problems.append(f"no restored tab picks up the repo override for {repo_path}")

    if problems:
        raise SystemExit("demo layout did not restore as specified:\n  " + "\n  ".join(problems))


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
                    # MONTTY_BIN is injected into every surface by the running
                    # app, so the usage text always comes from the binary that
                    # is driving this demo rather than whatever PATH resolves.
                    run_in(surface, "$MONTTY_BIN --help")
                else:
                    run_in(surface, f"cat {DEMO_ROOT}/fixtures/{fixture}.txt")
    time.sleep(1.5)


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


CLAUDE_PROMPTS = [
    "in one sentence, what does this service do?",
    "which file would I edit to change the listen port?",
    "what would you check first before adding a new endpoint?",
]

# Asked one at a time, and only while the startup banner is still in view.
BANNER_PROMPTS = [
    "and what should the first test for that endpoint cover?",
    "how would you keep the handler modules from sprawling?",
    "what belongs in the README before the first release?",
]


def ask(surface: dict, prompt: str, settle: float) -> None:
    post(f"/type?surface={surface['id']}", prompt)
    post(f"/key?surface={surface['id']}", "return")
    time.sleep(settle)


def banner_in_view(surface: dict) -> bool:
    """The startup banner names the model and the plan tier, and sits directly
    above the first prompt, so the first prompt still being on screen is the
    conservative test for whether any banner line is. Matched on a leading
    fragment short enough that no pane width can wrap it away."""
    marker = CLAUDE_PROMPTS[0][:15]
    return marker in get(f"/screen?surface={surface['id']}")["text"]


def start_claude(settle: float = 45.0) -> None:
    """Three exchanges, plus however many follow-ups it takes to scroll the
    startup banner out of the viewport. The demo shell's ZDOTDIR skips the
    owner's real dotfiles, so claude is resolved to an absolute path here rather
    than typed as a bare command that PATH might miss."""
    claude_bin = shutil.which("claude")
    if claude_bin is None:
        raise SystemExit("claude not found on PATH; cannot start the demo Claude pane")
    surfaces = get("/surfaces")
    for window in WINDOWS:
        for tab in window.tabs:
            if tab.claude_pane is None:
                continue
            surface = surface_for(tab.key, tab.claude_pane, surfaces)
            run_in(surface, "clear")
            run_in(surface, claude_bin)
            time.sleep(8)
            # A directory Claude has not seen asks to be trusted first, and
            # defaults to "No, exit" -- move down to "Yes, I trust this folder"
            # before confirming.
            post(f"/key?surface={surface['id']}", "down")
            post(f"/key?surface={surface['id']}", "return")
            time.sleep(2)
            pace = settle / len(CLAUDE_PROMPTS)
            for prompt in CLAUDE_PROMPTS:
                ask(surface, prompt, pace)
            for prompt in BANNER_PROMPTS:
                if not banner_in_view(surface):
                    break
                ask(surface, prompt, pace)
            if banner_in_view(surface):
                print("warning: the Claude Code banner is still in the hero pane's viewport")
            # Claude Code draws a suggested next prompt inside an empty
            # composer, which reads as stray text in the screenshot. A single
            # space replaces the suggestion and still renders as an empty
            # composer, and /type refuses a body that is only whitespace.
            post(f"/key?surface={surface['id']}", "space")
            time.sleep(1.0)


DOCS = Path(__file__).resolve().parent.parent / "docs"
RAW = DEMO_ROOT / "raw"

TARGET_WIDTH = 1400


def _config_background(config: str = GHOSTTY_CONFIG) -> tuple[int, int, int]:
    """The mat behind the composited windows, read from the pinned theme so it
    cannot drift away from what the terminals themselves render."""
    for line in config.splitlines():
        name, _, value = line.partition("=")
        if name.strip() == "background":
            hexed = value.strip().lstrip("#")
            return (int(hexed[0:2], 16), int(hexed[2:4], 16), int(hexed[4:6], 16))
    raise SystemExit("ghostty config has no background line to derive the backdrop from")


BACKDROP = _config_background()


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
    # Escape only cancels jump mode when it comes from a real key event: the
    # monitor that listens for it is an AppKit local event monitor, which a
    # synthetic /key request never passes through. Jumping back to hero's own
    # leaf exits jump mode the same way any other jump target would.
    post("/jump", hero["leaf_id"])
    time.sleep(0.5)

    # Each window is captured on its own; they are composited in postprocess().
    capture(hero["id"], RAW / "window-one.png")
    capture(second_window["id"], RAW / "window-two.png")

    # Last, because switching tabs moves the focus. goto_tab is window-scoped,
    # resolved from the surface named in the query string, so cli's id (fixed
    # at the top of this function) still names the right window afterward.
    cli_tab_index = 1 + next(i for i, t in enumerate(WINDOWS[0].tabs) if t.key == "w1t6")
    post("/action?surface=" + cli["id"], f"goto_tab:{cli_tab_index}")
    time.sleep(1)
    capture(cli["id"], RAW / "cli.png")


def cmd_build() -> None:
    subprocess.run(["just", "build"], check=True)
    stop()
    materialize_world()
    launch()
    wait_for_server()
    verify_layout()
    fill_panes()
    set_statuses()
    report()


def cmd_shoot() -> None:
    cmd_build()
    start_claude()
    capture_all()
    postprocess()
    stop()


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
    stop()
    shutil.rmtree(DEMO_ROOT, ignore_errors=True)
    print(f"removed {DEMO_ROOT}")


def main() -> None:
    commands = {
        "build": cmd_build,
        "shoot": cmd_shoot,
        "preview": cmd_preview,
        "clean": cmd_clean,
        "session": lambda: print(json.dumps(build_session(), indent=2)),
    }
    name = sys.argv[1] if len(sys.argv) > 1 else "build"
    if name not in commands:
        raise SystemExit(f"unknown command {name!r}; try {', '.join(commands)}")
    commands[name]()


if __name__ == "__main__":
    main()
