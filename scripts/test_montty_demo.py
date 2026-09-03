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
        self.assertEqual(flat[1], "/tmp/montty-demo/repos/acme-api")

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
        self.assertIn("/tmp/montty-demo/repos/infra", overrides)

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
