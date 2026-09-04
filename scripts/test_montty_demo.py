# ABOUTME: Stdlib unittest coverage for the montty demo world generator, run
# ABOUTME: without dependencies so it stays cheap to execute.
import json
import os
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

    def test_first_window_carries_the_five_tab_roster(self):
        names = [t["name"] for t in self.session["windows"][0]["tabs"]]
        self.assertEqual(names, ["", "MR !123 fix auth", "", "", ""])

    def test_auto_named_tabs_store_an_empty_name(self):
        first = self.session["windows"][0]["tabs"][0]
        self.assertEqual(first["name"], "")

    def test_leaf_directories_are_flat_alternating_pairs(self):
        first = self.session["windows"][0]["tabs"][0]
        flat = first["leafDirectories"]
        self.assertEqual(len(flat), 2)
        self.assertEqual(flat[1], "/private/tmp/montty-demo/repos/payments")

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
        self.assertEqual(tab["colorOverride"], ["green", "neutralBright"])

    def test_repo_override_is_keyed_by_absolute_repo_path(self):
        overrides = self.session["repoColorOverrides"]
        self.assertIn("/private/tmp/montty-demo/repos/dashboard", overrides)
        self.assertEqual(overrides["/private/tmp/montty-demo/repos/dashboard"], "magenta")

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

    def test_demo_uuid_returns_uppercase(self):
        result = demo.demo_uuid("test.key")
        self.assertTrue(result.isupper(), f"UUID should be uppercase, got: {result}")
        self.assertRegex(result, r"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$")


import tempfile


class MaterializeWorldTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        demo.materialize_world(self.root)

    def test_writes_a_branch_ref_a_git_directory_walk_can_read(self):
        head = self.root / "repos" / "payments" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/main")

    def test_orders_carries_a_different_branch(self):
        head = self.root / "repos" / "orders" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/feature/split-tender")

    def test_release_worktree_points_at_its_parent(self):
        git_file = self.root / "repos" / "payments-release" / ".git"
        self.assertTrue(git_file.is_file())
        self.assertIn("gitdir:", git_file.read_text())
        self.assertIn("payments", git_file.read_text())

    def test_scratch_has_no_git_so_it_renders_gray(self):
        self.assertTrue((self.root / "scratch").is_dir())
        self.assertFalse((self.root / "scratch" / ".git").exists())

    def test_pins_the_palette_so_colors_do_not_follow_the_users_theme(self):
        config = (self.root / "config" / "ghostty" / "config").read_text()
        self.assertIn("palette = 2=#00bb00", config)
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

    def test_payments_gets_a_real_source_tree_for_the_live_claude_pane(self):
        payments = self.root / "repos" / "payments"
        self.assertIn("payments", (payments / "Cargo.toml").read_text())
        self.assertIn("payment", (payments / "README.md").read_text().lower())
        self.assertIn("8080", (payments / "src" / "main.rs").read_text())

    def test_writes_a_veer_config_so_tool_calls_do_not_fail_closed(self):
        config = self.root / "config" / "veer" / "config.toml"
        self.assertTrue(config.is_file())

    def test_is_idempotent(self):
        demo.materialize_world(self.root)
        head = self.root / "repos" / "payments" / ".git" / "HEAD"
        self.assertEqual(head.read_text().strip(), "ref: refs/heads/main")


class DemoEnvTest(unittest.TestCase):
    def test_leaves_home_alone_so_the_claude_pane_stays_logged_in(self):
        env = demo.demo_env()
        self.assertEqual(env.get("HOME"), os.environ.get("HOME"))

    def test_silences_the_claude_code_updater_notice(self):
        self.assertEqual(demo.demo_env()["DISABLE_AUTOUPDATER"], "1")

    def test_strips_the_parent_claude_session_markers(self):
        os.environ["CLAUDE_CODE_CHILD_SESSION"] = "1"
        self.addCleanup(os.environ.pop, "CLAUDE_CODE_CHILD_SESSION", None)
        env = demo.demo_env()
        self.assertEqual([k for k in env if k.startswith("CLAUDE_CODE_")], [])


if __name__ == "__main__":
    unittest.main()
