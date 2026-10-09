import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
import inject
import struct
import plistlib
import contextlib
import io
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]

class RateAdaptTests(unittest.TestCase):
    def tearDown(self):
        inject.configure_profile("7.0.255")

    def test_native_distance_sites_and_retired_window(self):
        for version, site, replay in (("7.0.255",0x100863DFC,0x101468190),
                                     ("7.0.256",0x100865B50,0x10146C1C0)):
            inject.configure_profile(version)
            hooks = {name:(address,slot,expect) for name,address,slot,expect in inject.BRK_HOOKS}
            self.assertEqual(hooks["native_flow_note"],(site,replay,"00b8a10e"))
            selected,_=inject.features_selected([])
            self.assertIn("rate_flow",selected)
            self.assertNotIn("adapt_window",inject.sites_for(selected))
            self.assertIn("flow_ui",inject.sites_for(selected))
            native=[h for h in inject.BRK_HOOKS if h[0].startswith("native_flow_")]
            self.assertEqual(len(native),6)
            for name,address,slot,expect in native:
                self.assertIsNone(inject.pc_relative_kind(struct.unpack('<I',bytes.fromhex(expect))[0]))
                self.assertNotIn(slot,[h[2] for h in inject.BRK_HOOKS if h[0]!=name])

    def test_native_distance_replays_in_isolated_binary(self):
        inject.configure_profile('7.0.256')
        hooks=[h for h in inject.BRK_HOOKS if h[0].startswith('native_flow_')]
        data=bytearray(0x146c220)
        struct.pack_into('<III',data,0,0xfeedfacf,0x100000c,0)
        for name,site,replay,expect in hooks: data[site-0x100000000:site-0x100000000+4]=bytes.fromhex(expect)
        inject.patch_brk_hooks(data,{h[0] for h in hooks})
        for name,site,replay,expect in hooks:
            self.assertEqual(data[site-0x100000000:site-0x100000000+4],inject.BRK_INSN)
            self.assertEqual(data[replay-0x100000000:replay-0x100000000+4],bytes.fromhex(expect))

    def test_old_flow_library_rejected_before_any_write(self):
        for version in ('7.0.255','7.0.256'):
            with tempfile.TemporaryDirectory() as temp:
                main=Path(temp)/'Arc-mobile'
                main.write_bytes(struct.pack('<8I',0xfeedfacf,0x100000c,0,2,0,0,0,0))
                (main.parent/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':version}))
                lib=main.parent/'libxrcdemo.dylib'
                lib.write_bytes(b'xrc-profile:7.0.256 practice-timing v1 practice-adapt v1 practice-live-flow v1 autoplay-eve v1 chain-guard v1')
                before=main.read_bytes(); output=io.StringIO()
                with mock.patch.object(inject,'MAIN',str(main)),mock.patch.object(inject.sys,'argv',['inject.py','--brk','--features','rate_flow']),mock.patch.object(inject,'find_dylibs',return_value=[str(lib)]),mock.patch.object(inject.shutil,'copy2') as copy,contextlib.redirect_stdout(output):
                    with self.assertRaises(SystemExit) as error: inject.main()
                    self.assertEqual(error.exception.code,3)
                    self.assertIn('practice-native-flow v2',output.getvalue())
                    copy.assert_not_called()
                self.assertEqual(main.read_bytes(),before)

    def test_compensation_preserves_real_time_and_no_accumulation(self):
        compiler=os.environ.get("CC") or shutil.which("cc") or shutil.which("clang")
        if not compiler:
            self.skipTest("C compiler unavailable; macOS build runs this test")
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/("adapt.exe" if os.name=="nt" else "adapt")
            args=[compiler,"-I"+str(ROOT/"src/gameplay"),str(ROOT/"src/tests/rate_adapt_math.c"),"-o",str(output)]
            if os.name != "nt": args.append("-lm")
            subprocess.run(args,check=True,capture_output=True,text=True)
            subprocess.run([str(output)],check=True,capture_output=True,text=True)
