import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ReplaySeekTests(unittest.TestCase):
    def test_restoration_is_independent_of_score_policy(self):
        source = (ROOT / "src/gameplay/XRCReplay.m").read_text(encoding="utf-8")
        seek = source.split("void xrc_replay_seek(", 1)[1].split("static int      s_nh_on", 1)[0]
        self.assertNotIn("s_reset_score", seek)
        self.assertIn("rpf_reset_dispatch(ng, target, previous)", seek)
        self.assertIn("if (s_reset_score && !s_no_score) rpf_score_reset(ng, T);", source)
        watcher = source.split("static void rpf_fast_tick", 1)[1]
        self.assertNotIn("s_reset_score", watcher.split("void xrc_replay_start", 1)[0])
        config = (ROOT / "src/core/XRCConfig.m").read_text(encoding="utf-8")
        self.assertIn('p[@"resetScore"] = p[@"replayArm"] ?: @NO', config)

    def test_inline_rebuild_runs_after_all_state_restoration(self):
        source = (ROOT / "src/gameplay/XRCReplay.m").read_text(encoding="utf-8")
        revive = source.split("static void rpf_revive(uint64_t", 1)[1]
        revive, reset = revive.split("static void rpf_reset(uint64_t", 1)
        reset = reset.split("static int rpf_node_ok", 1)[0]
        self.assertNotIn("rpf_rebuild_dispatch(", revive)
        self.assertIn("rpf_revive_dispatch(scene, s_reg_pend_n)", revive)
        rebuild = reset.index("rpf_rebuild_dispatch(")
        for step in ("rpf_revive(", "rpf_clear_touch_state(",
                     "rpf_clear_buckets(", "rpf_open_gates("):
            self.assertLess(reset.index(step), rebuild)
