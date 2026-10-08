import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
import inject

ROOT = Path(__file__).resolve().parents[1]

class RateAdaptTests(unittest.TestCase):
    def tearDown(self):
        inject.configure_profile("7.0.255")

    def test_matching_window_sites_and_release_selection(self):
        for version, site, replay in (("7.0.255",0x10091C51C,0x101468188),
                                     ("7.0.256",0x10091E620,0x10146C1B8)):
            inject.configure_profile(version)
            hooks = {name:(address,slot,expect) for name,address,slot,expect in inject.BRK_HOOKS}
            self.assertEqual(hooks["adapt_window"],(site,replay,"681640f9"))
            selected,_=inject.features_selected([])
            self.assertIn("rate_flow",selected)
            self.assertNotIn("flow_ui",inject.sites_for(selected))
            other_slots=[h[2] for h in inject.BRK_HOOKS if h[0] != "adapt_window"]
            self.assertNotIn(replay,other_slots)

    def test_compensation_preserves_real_time_and_no_accumulation(self):
        compiler=os.environ.get("CC") or shutil.which("cc") or shutil.which("clang")
        if not compiler:
            self.skipTest("C compiler unavailable; macOS build runs this test")
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/("adapt.exe" if os.name=="nt" else "adapt")
            args=[compiler,"-I"+str(ROOT/"src/gameplay"),str(ROOT/"tests/rate_adapt_math.c"),"-o",str(output)]
            if os.name != "nt": args.append("-lm")
            subprocess.run(args,check=True,capture_output=True,text=True)
            subprocess.run([str(output)],check=True,capture_output=True,text=True)
