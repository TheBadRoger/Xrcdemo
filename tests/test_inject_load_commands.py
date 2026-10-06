import struct
import unittest

import inject


def image(commands):
    body = b"".join(commands)
    header = struct.pack("<8I", 0xFEEDFACF, 0x0100000C, 0, 2,
                         len(commands), len(body), 0, 0)
    return bytearray(header + body + b"\0" * 256 + b"\x01")


class LoadCommandsTests(unittest.TestCase):
    def test_new_injection_uses_apple_command_value(self):
        data = image([])
        inject.insert_load_commands_inplace(data, 0)
        commands = inject.parse_load_commands(data, 0)[2]
        self.assertEqual(commands[0][0], 0xC)
        self.assertTrue(inject.has_load_dylib(data, 0, inject.INJECT_NAME))
        self.assertTrue(inject.has_rpath(data, 0, "@executable_path/Frameworks"))

    def test_old_invalid_command_is_rejected_and_repaired_in_place(self):
        bad = bytearray(inject.build_load_dylib_cmd(inject.INJECT_NAME))
        struct.pack_into("<I", bad, 0, 0x8000000C)
        data = image([bad, inject.build_rpath_cmd("@executable_path/Frameworks")])
        original = bytes(data)
        self.assertFalse(inject.has_load_dylib(data, 0, inject.INJECT_NAME))
        inject.insert_load_commands_inplace(data, 0)
        self.assertTrue(inject.has_load_dylib(data, 0, inject.INJECT_NAME))
        expected = bytearray(original)
        struct.pack_into("<I", expected, 32, 0xC)
        self.assertEqual(data, expected)
        repaired = bytes(data)
        inject.insert_load_commands_inplace(data, 0)
        self.assertEqual(data, repaired)


if __name__ == "__main__":
    unittest.main()
