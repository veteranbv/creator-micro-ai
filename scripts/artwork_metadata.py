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


if __name__ == "__main__":
    assets = pathlib.Path(__file__).resolve().parents[1] / "assets"
    for name in ("icon.png", "social-card.png"):
        file = assets / name
        before = file.read_bytes()
        after = sanitized(before)
        assert [raw for kind, raw in chunks(before) if kind in RENDER_CHUNKS] == [raw for _, raw in chunks(after)]
        file.write_bytes(after)
        print(f"Validated artwork metadata: {name}")
