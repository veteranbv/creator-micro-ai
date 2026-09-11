"""Synthetic PNG chunks test metadata handling without embedding vendor assets."""
import pathlib
import struct
import sys
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from artwork_metadata import SIGNATURE, metadata_clean, sanitized


def chunk(kind, data=b""):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


class ArtworkTests(unittest.TestCase):
    def test_strips_metadata_and_preserves_render_chunks(self):
        header = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        pixels = chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
        clean = SIGNATURE + header + pixels + chunk(b"IEND")
        with_metadata = SIGNATURE + header + chunk(b"tEXt", b"Comment\x00Example") + pixels + chunk(b"IEND")
        self.assertEqual(sanitized(with_metadata), clean)
        self.assertTrue(metadata_clean(clean))
        self.assertFalse(metadata_clean(with_metadata))

    def test_rejects_truncation_bad_crc_and_trailing_data(self):
        self.assertFalse(metadata_clean(SIGNATURE + b"\x00"))
        self.assertFalse(metadata_clean(SIGNATURE + chunk(b"IHDR")[:-1] + b"X"))
        self.assertFalse(metadata_clean(SIGNATURE + chunk(b"IHDR") + chunk(b"IEND") + b"extra"))


if __name__ == "__main__":
    unittest.main()
