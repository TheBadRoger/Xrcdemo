import unittest

import inject
from test_inject_load_commands import image


class FlowRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.plan = [(48, "4631881a", "e603082a"), (64, "00318a1a", "e0030a2a")]
        self.data = image([])
        for offset, original, _ in self.plan:
            self.data[offset:offset + 4] = bytes.fromhex(original)

    def test_reapply_and_disable_restore_original_image(self):
        original = self.data[:]
        inject.patch_flow_runtime(self.data, True, self.plan)
        for offset, _, replacement in self.plan:
            self.assertEqual(self.data[offset:offset + 4].hex(), replacement)
        patched = self.data[:]
        inject.patch_flow_runtime(self.data, True, self.plan)
        self.assertEqual(self.data, patched)
        inject.patch_flow_runtime(self.data, False, self.plan)
        self.assertEqual(self.data, original)

    def test_wrong_version_is_rejected_before_any_write(self):
        self.data[64:68] = b"\xff" * 4
        before = self.data[:]
        with self.assertRaises(RuntimeError):
            inject.patch_flow_runtime(self.data, True, self.plan)
        self.assertEqual(self.data, before)
