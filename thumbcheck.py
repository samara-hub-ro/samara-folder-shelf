"""Filter candidate thumbnails down to files that are safe to hand to Qt.

    python3 -I thumbcheck.py <wanted>   < scan.sh output

Reads scan.sh's stdout line by line. Every line passes through unchanged
except `CAND<TAB><path>`, which is checked and, if it passes, re-emitted as
`THUMB<TAB><path>` (at most <wanted> of them).

The shelf draws these files as soon as a tile is on screen, inside the shared
desktop shell, and the files come from folders other people can drop things
into. Qt's image readers will decode whatever they are given, so what reaches
them has to be small and plain:

  * a regular file, opened without following a link and without blocking;
  * at most MAX_BYTES long and at most MAX_PIXELS in area;
  * whose first bytes match its extension (png, jpg, gif or webp only);
  * and, for PNG, whose chunk list is walked with bounded reads: no zTXt or
    iTXt at all, a few small tEXt/iCCP chunks at most, a bounded chunk count,
    lengths that fit the file, and a closing IEND. A PNG made of hundreds of
    compressed text chunks is exactly the shape that makes libpng retain far
    more memory than the file is long.

A file that fails any check is simply not offered as a thumbnail.
"""

import os
import struct
import sys

MAX_BYTES = 8 * 1024 * 1024
MAX_PIXELS = 40_000_000
MAX_CHUNKS = 128
MAX_TEXT_CHUNKS = 4
MAX_TEXT_LEN = 4096
MAX_ICC_LEN = 65536

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def png_ok(fd, size):
    os.lseek(fd, 0, os.SEEK_SET)
    head = os.read(fd, 8 + 8 + 13)
    if len(head) < 29 or head[:8] != PNG_SIG:
        return False
    length, kind = struct.unpack(">I4s", head[8:16])
    if kind != b"IHDR" or length != 13:
        return False
    width, height = struct.unpack(">II", head[16:24])
    if width == 0 or height == 0 or width * height > MAX_PIXELS:
        return False
    pos = 8
    seen = 0
    text = 0
    icc = 0
    while pos + 12 <= size:
        seen += 1
        if seen > MAX_CHUNKS:
            return False
        os.lseek(fd, pos, os.SEEK_SET)
        hdr = os.read(fd, 8)
        if len(hdr) < 8:
            return False
        length, kind = struct.unpack(">I4s", hdr)
        if length > 0x7FFFFFFF or pos + 12 + length > size:
            return False
        if kind in (b"zTXt", b"iTXt"):
            return False
        if kind == b"tEXt":
            text += 1
            if text > MAX_TEXT_CHUNKS or length > MAX_TEXT_LEN:
                return False
        elif kind == b"iCCP":
            icc += 1
            if icc > 1 or length > MAX_ICC_LEN:
                return False
        elif kind == b"IEND":
            return True
        pos += 12 + length
    return False


def magic_ok(ext, head):
    if ext == "png":
        return head[:8] == PNG_SIG
    if ext in ("jpg", "jpeg"):
        return head[:3] == b"\xff\xd8\xff"
    if ext == "gif":
        return head[:6] in (b"GIF87a", b"GIF89a")
    if ext == "webp":
        return head[:4] == b"RIFF" and head[8:12] == b"WEBP"
    return False


def safe(path):
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    if ext not in ("png", "jpg", "jpeg", "gif", "webp"):
        return False
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC
    try:
        fd = os.open(path, flags)
    except OSError:
        return False
    try:
        st = os.fstat(fd)
        import stat as statmod
        if not statmod.S_ISREG(st.st_mode) or st.st_size < 32 or st.st_size > MAX_BYTES:
            return False
        head = os.read(fd, 16)
        if not magic_ok(ext, head):
            return False
        if ext == "png":
            return png_ok(fd, st.st_size)
        return True
    except OSError:
        return False
    finally:
        os.close(fd)


def main():
    try:
        wanted = int(sys.argv[1])
    except (IndexError, ValueError):
        wanted = 0
    shown = 0
    out = sys.stdout
    for line in sys.stdin:
        if line.startswith("CAND\t"):
            if shown < wanted:
                path = line[5:].rstrip("\n")
                if path and safe(path):
                    shown += 1
                    out.write("THUMB\t" + path + "\n")
            continue
        out.write(line)
    out.flush()


if __name__ == "__main__":
    main()
