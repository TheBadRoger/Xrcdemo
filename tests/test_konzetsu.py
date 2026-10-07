import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import contextlib
import io
import plistlib
from unittest import mock
from pathlib import Path
import inject

ROOT=Path(__file__).resolve().parents[1]
NAMES={'konzetsu_chart','konzetsu_id','konzetsu_active','konzetsu_score','konzetsu_hpbar','konzetsu_info'}

class KonzetsuTests(unittest.TestCase):
    def tearDown(self):
        inject.configure_profile('7.0.255')

    def test_supported_version_and_complete_site_set(self):
        inject.configure_profile('7.0.255')
        features,_=inject.features_selected(['--profile','release'])
        self.assertNotIn('konzetsu', features)
        with self.assertRaises(SystemExit):
            inject.features_selected(['--features','konzetsu'])
        inject.configure_profile('7.0.256')
        features,_=inject.features_selected(['--profile','release'])
        self.assertIn('konzetsu',features)
        self.assertEqual(NAMES, NAMES & inject.sites_for(features))
        hooks=[h for h in inject.BRK_HOOKS if h[0] in NAMES]
        self.assertEqual(len(hooks),6)
        for name,site,replay,expect in hooks:
            self.assertEqual(len(bytes.fromhex(expect)),4)
            self.assertIsNone(inject.pc_relative_kind(struct.unpack('<I',bytes.fromhex(expect))[0]))
        slots=[h[2] for h in inject.BRK_HOOKS if h[2]]
        self.assertEqual(len(slots),len(set(slots)))

    def test_hook_bytes_and_replays_in_isolated_binary(self):
        inject.configure_profile('7.0.256')
        hooks=[h for h in inject.BRK_HOOKS if h[0] in NAMES]
        # A thin arm64 Mach-O header is sufficient for this patcher's slice detection.
        data=bytearray(0x146c200)
        struct.pack_into('<III',data,0,0xfeedfacf,0x100000c,0)
        for name,site,replay,expect in hooks:
            off=site-0x100000000
            data[off:off+4]=bytes.fromhex(expect)
        inject.patch_brk_hooks(data,NAMES)
        for name,site,replay,expect in hooks:
            off=site-0x100000000
            rf=replay-0x100000000
            self.assertEqual(data[off:off+4],inject.BRK_INSN)
            self.assertEqual(data[rf:rf+4],bytes.fromhex(expect))
            word=struct.unpack_from('<I',data,rf+4)[0]
            self.assertEqual(word,inject.encode_b(replay+4,site+4))
        # Applying again must not overwrite the already recorded instructions.
        snapshot=bytes(data)
        inject.patch_brk_hooks(data,NAMES)
        self.assertEqual(bytes(data),snapshot)

    def test_option_mapping_and_scaled_intervals(self):
        compiler=os.environ.get('CC') or shutil.which('cc') or shutil.which('clang')
        if not compiler:
            self.skipTest('C compiler unavailable locally; macOS workflow runs this test')
        with tempfile.TemporaryDirectory() as temp:
            output=Path(temp)/('konzetsu.exe' if os.name=='nt' else 'konzetsu')
            subprocess.run([compiler,'-I'+str(ROOT/'src/gameplay'),str(ROOT/'tests/konzetsu_math.c'),'-o',str(output)],check=True,capture_output=True,text=True)
            subprocess.run([str(output)],check=True,capture_output=True,text=True)

    def test_command_resolves_game_version_before_feature_selection(self):
        inject.configure_profile('7.0.255')
        with tempfile.TemporaryDirectory() as temp:
            main=Path(temp)/'Arc-mobile'
            main.write_bytes(b'')
            (main.parent/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'7.0.256'}))
            output=io.StringIO()
            with mock.patch.object(inject,'MAIN',str(main)), mock.patch.object(inject.sys,'argv',['inject.py','--brk']), mock.patch.object(inject,'find_dylibs',side_effect=FileNotFoundError('fixture')), contextlib.redirect_stdout(output):
                with self.assertRaises(SystemExit):
                    inject.main()
                self.assertIn('[+] konzetsu',output.getvalue())

    def test_old_artifact_is_rejected_before_any_deployment_write(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            main=root/'Arc-mobile'
            main.write_bytes(struct.pack('<8I',0xfeedfacf,0x100000c,0,2,0,0,0,0))
            (root/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'7.0.256'}))
            library=root/'libxrcdemo.dylib'
            library.write_bytes(b'xrc-profile:7.0.256 practice-timing v1 practice-flow v2 autoplay-eve v1 chain-guard v1')
            before=main.read_bytes()
            output=io.StringIO()
            with mock.patch.object(inject,'MAIN',str(main)), mock.patch.object(inject.sys,'argv',['inject.py','--brk']), mock.patch.object(inject,'find_dylibs',return_value=[str(library)]), mock.patch.object(inject.shutil,'copy2') as copy, contextlib.redirect_stdout(output):
                with self.assertRaises(SystemExit) as error:
                    inject.main()
                self.assertEqual(error.exception.code,3)
                self.assertIn("konzetsu-practice v1",output.getvalue())
                copy.assert_not_called()
            self.assertEqual(main.read_bytes(),before)
