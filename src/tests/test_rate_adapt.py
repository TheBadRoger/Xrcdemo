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

    def test_numeric_flow_sites_and_retired_render_sites(self):
        for version in ('7.0.255','7.0.256'):
            inject.configure_profile(version)
            selected,_=inject.features_selected([])
            sites=inject.sites_for(selected)
            self.assertIn('flow_setter',sites)
            self.assertFalse(any(n.startswith('native_flow_') for n in sites))
            self.assertNotIn('adapt_window',sites)
            self.assertEqual(len(inject.RETIRED_FLOW_HOOKS),7)

    def test_migration_restores_render_instructions_and_is_idempotent(self):
        for version in ('7.0.255','7.0.256'):
            inject.configure_profile(version)
            data=bytearray(0x146d000)
            struct.pack_into('<III',data,0,0xfeedfacf,0x100000c,0)
            for name,site,replay,expected in inject.RETIRED_FLOW_HOOKS:
                off=site-0x100000000; rf=replay-0x100000000
                data[off:off+4]=inject.BRK_INSN
                data[rf:rf+8]=bytes.fromhex(expected)+struct.pack('<I',inject.encode_b(replay+4,site+4))
            inject.restore_retired_flow(data)
            for name,site,replay,expected in inject.RETIRED_FLOW_HOOKS:
                self.assertEqual(data[site-0x100000000:site-0x100000000+4],bytes.fromhex(expected))
                self.assertEqual(data[replay-0x100000000:replay-0x100000000+8],b'\0'*8)
            before=data[:]; inject.restore_retired_flow(data);self.assertEqual(data,before)
            name,site,replay,expected=inject.RETIRED_FLOW_HOOKS[-1]
            data[site-0x100000000:site-0x100000000+4]=b'\xff'*4
            before=data[:]
            with self.assertRaises(RuntimeError):inject.restore_retired_flow(data)
            self.assertEqual(data,before)

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
                    self.assertIn('practice-value-flow v1',output.getvalue())
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
