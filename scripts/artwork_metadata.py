"""Validate and remove non-rendering PNG metadata without changing pixel data."""
import pathlib
import struct
import zlib

SIGNATURE = b"\x89PNG\r\n\x1a\n"
RENDER_CHUNKS = {b"IHDR", b"PLTE", b"tRNS", b"IDAT", b"IEND", b"sRGB", b"gAMA", b"cHRM", b"iCCP"}


def chunks(data):
    if not data.startswith(SIGNATURE):
        raise ValueError("Not a PNG")
    offset = len(SIGNATURE)
    result = []
    while offset + 12 <= len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        end = offset + size + 12
        if end > len(data):
            raise ValueError("Truncated PNG chunk")
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack_from(">I", data, end - 4)[0]
        if zlib.crc32(kind + payload) != crc:
            raise ValueError("Invalid PNG checksum")
        result.append((kind, data[offset:end]))
        offset = end
        if kind == b"IEND":
            break
    if offset != len(data) or not result or result[0][0] != b"IHDR" or result[-1][0] != b"IEND":
        raise ValueError("Invalid PNG structure")
    return result


def sanitized(data):
    result = []
    for kind, raw in chunks(data):
        if kind not in RENDER_CHUNKS and not kind[0] & 32:
            raise ValueError("Unknown critical PNG chunk")
        if kind in RENDER_CHUNKS:
            result.append(raw)
    return SIGNATURE + b"".join(result)


def metadata_clean(data):
    try:
        return sanitized(data) == data
    except ValueError:
        return False


def icon_entries(data):
    if len(data) < 8 or data[:4] != b"icns" or struct.unpack_from(">I", data, 4)[0] != len(data):
        raise ValueError("Invalid ICNS header")
    offset, entries = 8, []
    while offset + 8 <= len(data):
        kind, size = struct.unpack_from(">4sI", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid ICNS entry")
        entries.append((kind, data[offset + 8:offset + size]))
        offset += size
    if offset != len(data) or not entries:
        raise ValueError("Truncated ICNS")
    return entries


def sanitized_icon(data):
    entries = [(kind, sanitized(payload) if payload.startswith(SIGNATURE) else payload)
               for kind, payload in icon_entries(data)]
    # iconutil can insert metadata again while packaging clean source PNGs.
    table = b"".join(struct.pack(">4sI", kind, len(payload) + 8)
                     for kind, payload in entries if kind != b"TOC ")
    result = b"".join(struct.pack(">4sI", kind, len(payload) + 8) + payload
                      for kind, payload in [(kind, table if kind == b"TOC " else payload)
                                            for kind, payload in entries])
    return b"icns" + struct.pack(">I", len(result) + 8) + result


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", type=pathlib.Path)
    args = parser.parse_args()
    assets = pathlib.Path(__file__).resolve().parents[1] / "assets"
    for file in args.files or [assets / "icon.png", assets / "social-card.png"]:
        before = file.read_bytes()
        if file.suffix.lower() == ".icns":
            after = sanitized_icon(before)
        else:
            after = sanitized(before)
            assert [raw for kind, raw in chunks(before) if kind in RENDER_CHUNKS] == [raw for _, raw in chunks(after)]
        file.write_bytes(after)
        print(f"Validated artwork metadata: {file.name}")
