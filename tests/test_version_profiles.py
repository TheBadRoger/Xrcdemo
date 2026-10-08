import unittest

import inject


class VersionProfileTests(unittest.TestCase):
    def test_retired_pack_switches_are_not_injected(self):
        for version in ("7.0.255", "7.0.256"):
            inject.configure_profile(version)
            for profile in ("release", "dev"):
                features, _ = inject.features_selected(["--profile", profile])
                self.assertNotIn("unlock_lock", features)
                self.assertTrue({"lock_fv", "lock_do", "fv_gate"}.isdisjoint(inject.sites_for(features)))
        with self.assertRaises(SystemExit):
            inject.features_selected(["--features", "unlock_lock"])

    def tearDown(self):
        inject.configure_profile("7.0.255")

    def test_switching_back_restores_baseline(self):
        inject.configure_profile("7.0.255")
        original_hooks = list(inject.BRK_HOOKS)
        inject.configure_profile("7.0.256")
        self.assertEqual(inject.STUB_ENTRY_FILE, 0x920788)
        self.assertNotEqual(inject.BRK_HOOKS, original_hooks)
        self.assertTrue(all(expected for _, _, _, expected in inject.BRK_HOOKS))
        inject.configure_profile("7.0.255")
        self.assertEqual(inject.STUB_ENTRY_FILE, 0x91E684)
        self.assertEqual(inject.BRK_HOOKS, original_hooks)

    def test_unknown_version_is_rejected(self):
        with self.assertRaises(RuntimeError):
            inject.configure_profile("7.0.257")

    def test_practice_hooks_have_distinct_replay_slots(self):
        for version in ("7.0.255", "7.0.256"):
            inject.configure_profile(version)
            selected = {name: (site, replay, original) for name, site, replay, original in inject.BRK_HOOKS}
            for name in ("timing_input", "timing_arc_input", "flow_ui"):
                site, replay, original = selected[name]
                self.assertEqual(site % 4, 0)
                self.assertEqual(replay % 8, 0)
                self.assertEqual(len(bytes.fromhex(original)), 4)
            replays = [replay for _, replay, _ in selected.values() if replay]
            self.assertEqual(len(replays), len(set(replays)))
            enabled, _ = inject.features_selected(["--profile", "release"])
            self.assertIn("judge_time_lock", enabled)
            self.assertIn("rate_flow", enabled)
