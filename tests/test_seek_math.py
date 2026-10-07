import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class SeekMathTests(unittest.TestCase):
    def test_real_seek_math_preserves_offset_and_rejects_stale_positions(self):
        compiler = os.environ.get("CC") or shutil.which("cc") or shutil.which("clang")
        local = ROOT / "ios/deployment/tools/tinycc/tcc/tcc.exe"
        if not compiler and local.exists():
            compiler = str(local)
        if not compiler:
            self.skipTest("C compiler unavailable; run this test on macOS with the plugin build")
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / ("seek.exe" if os.name == "nt" else "seek")
            subprocess.run([compiler, "-I" + str(ROOT / "src/gameplay"),
                            str(ROOT / "tests/seek_math.c"), "-o", str(output)],
                           check=True, capture_output=True, text=True)
            subprocess.run([str(output)], check=True, capture_output=True, text=True)
