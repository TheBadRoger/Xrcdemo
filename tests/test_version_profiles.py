import unittest

import inject


class VersionProfileTests(unittest.TestCase):
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
