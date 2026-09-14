"""Synthetic PNG chunks test metadata handling without embedding vendor assets."""
import pathlib
import struct
import sys
import unittest
import zlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "scripts"))
from artwork_metadata import SIGNATURE, icon_entries, metadata_clean, sanitized, sanitized_icon


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

    def test_packaged_icon_has_only_clean_embedded_pngs(self):
        data = (pathlib.Path(__file__).resolve().parents[1] / "assets" / "AppIcon.icns").read_bytes()
        self.assertEqual(data[:4], b"icns")
        self.assertEqual(struct.unpack_from(">I", data, 4)[0], len(data))
        offset, images = 8, 0
        while offset < len(data):
            size = struct.unpack_from(">I", data, offset + 4)[0]
            self.assertGreaterEqual(size, 8)
            self.assertLessEqual(offset + size, len(data))
            payload = data[offset + 8:offset + size]
            if payload.startswith(SIGNATURE):
                self.assertTrue(metadata_clean(payload), "Embedded icon PNG needs sanitization")
                images += 1
            offset += size
        self.assertGreater(images, 0)
        self.assertEqual(offset, len(data))

    def test_exif_removed_without_changing_pixels(self):
        header = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        pixels = chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00"))
        clean = SIGNATURE + header + pixels + chunk(b"IEND")
        self.assertEqual(sanitized(SIGNATURE + header + chunk(b"eXIf", b"synthetic") + pixels + chunk(b"IEND")), clean)

    def test_icon_sanitizer_updates_lengths_and_preserves_image_data(self):
        png = SIGNATURE + chunk(b"IHDR") + chunk(b"eXIf", b"synthetic") + chunk(b"IDAT", b"pixels") + chunk(b"IEND")
        image = struct.pack(">4sI", b"ic07", len(png) + 8) + png
        table = struct.pack(">4sI", b"TOC ", 16) + image[:8]
        icon = b"icns" + struct.pack(">I", 8 + len(table) + len(image)) + table + image
        result = sanitized_icon(icon)
        entries = icon_entries(result)
        self.assertEqual(entries[1], (b"ic07", sanitized(png)))
        self.assertEqual(entries[0], (b"TOC ", struct.pack(">4sI", b"ic07", len(sanitized(png)) + 8)))
        self.assertEqual(sanitized_icon(result), result)
        for invalid in (b"icns", result[:-1], result + b"extra", b"icns" + struct.pack(">I", 16) + b"ic07\x00\x00\x00\x00"):
            with self.assertRaises(ValueError):
                sanitized_icon(invalid)


if __name__ == "__main__":
    unittest.main()
