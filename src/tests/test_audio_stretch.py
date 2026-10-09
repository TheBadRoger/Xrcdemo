import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AudioStretchTests(unittest.TestCase):
    def test_pitch_stereo_and_seek_history(self):
        compiler = os.environ.get("CXX") or shutil.which("c++") or shutil.which("clang++")
        if not compiler:
            self.skipTest("C++ compiler unavailable")
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / ("audio.exe" if os.name == "nt" else "audio")
            command = [compiler, "-std=c++17", "-O2",
                            "-I" + str(ROOT / "src/gameplay"),
                            "-I" + str(ROOT / "src/core"),
                            "-I" + str(ROOT / "src/vendor"),
                            str(ROOT / "src/tests/audio_stretch.cpp"),
                            "-o", str(output)]
            if sys.platform == "darwin":
                command += ["-DSIGNALSMITH_USE_ACCELERATE", "-framework", "Accelerate"]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            result = subprocess.run([str(output)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
