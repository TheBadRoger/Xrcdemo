import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class PracticeMathTests(unittest.TestCase):
    def test_compiled_judgment_boundaries_and_flow_validation(self):
        compiler = os.environ.get("CC") or shutil.which("cc") or shutil.which("clang")
        local = ROOT / "ios/deployment/tools/tinycc/tcc/tcc.exe"
        if not compiler and local.exists():
            compiler = str(local)
        if not compiler:
            self.skipTest("C compiler unavailable; macOS build runs this test")
        with tempfile.TemporaryDirectory() as temp:
            executable = Path(temp) / ("math.exe" if os.name == "nt" else "math")
            command = [compiler, "-I" + str(ROOT / "src/gameplay"),
                       str(ROOT / "tests/practice_math.c"), "-o", str(executable)]
            if os.name != "nt":
                command.append("-lm")
            subprocess.run(command, check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], check=True, capture_output=True, text=True)
