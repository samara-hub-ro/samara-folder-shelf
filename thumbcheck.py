"""Filter candidate thumbnails down to files that are safe to hand to Qt.

    python3 -I thumbcheck.py <wanted>   < scan.sh output

Reads scan.sh's stdout line by line. Every line passes through unchanged
except `CAND<TAB><path>`, which is checked and, if it passes, re-emitted as
`THUMB<TAB><path>` (at most <wanted> of them).

The shelf draws these files as soon as a tile is on screen, inside the shared
desktop shell, and the files come from folders other people can drop things
into. Qt's image readers will decode whatever they are given, so what reaches
them has to be small and plain:

  * a regular file, opened without following a link and without blocking, and
    read once, in full, from that descriptor;
  * at most MAX_BYTES long and at most MAX_PIXELS in area;
  * whose first bytes match its extension (png, jpg, gif or webp only);
  * and, for PNG, whose chunk list is walked with bounded reads: no zTXt or
    iTXt at all, a few small tEXt/iCCP chunks at most, a bounded chunk count,
    lengths that fit the file, and a closing IEND. A PNG made of hundreds of
    compressed text chunks is exactly the shape that makes libpng retain far
    more memory than the file is long.

The checks are made on the bytes themselves, read once from the descriptor
that was opened, and a passing file is offered as a *private snapshot* of those
bytes (a file in a 0700 directory under $XDG_RUNTIME_DIR, named by hash), never
as the original path. Qt reopens whatever path it is given, and the original
sits in a folder somebody else may be writing to: between the check and the
decode it could become a FIFO, a symlink or a different image. The snapshot is
ours alone and never changes after it is written.

A file that fails any check is simply not offered as a thumbnail.
"""

import hashlib
import os
import stat
import struct
import sys
import time

MAX_BYTES = 8 * 1024 * 1024
MAX_PIXELS = 40_000_000
MAX_CHUNKS = 128
MAX_TEXT_CHUNKS = 4
MAX_TEXT_LEN = 4096
MAX_ICC_LEN = 65536
KEEP = 300

PNG_SIG = b"\x89PNG\r\n\x1a\n"


def png_ok(data):
    size = len(data)
    if size < 33 or data[:8] != PNG_SIG:
        return False
    length, kind = struct.unpack(">I4s", data[8:16])
    if kind != b"IHDR" or length != 13:
        return False
    width, height = struct.unpack(">II", data[16:24])
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
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
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


def cache_dir():
    """The private snapshot directory, created 0700 and checked, or None."""
    base = os.environ.get("XDG_RUNTIME_DIR", "")
    if not base.startswith("/"):
        return None
    path = os.path.join(base, "folder-shelf-thumbs")
    try:
        os.mkdir(path, 0o700)
    except FileExistsError:
        pass
    except OSError:
        return None
    try:
        st = os.lstat(path)
    except OSError:
        return None
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or (st.st_mode & 0o077):
        return None
    return path


def prune(directory):
    """Keep the snapshot directory small: newest KEEP files, none older than a day."""
    try:
        entries = []
        with os.scandir(directory) as it:
            for e in it:
                try:
                    entries.append((e.stat(follow_symlinks=False).st_mtime, e.path))
                except OSError:
                    pass
        entries.sort(reverse=True)
        cutoff = time.time() - 86400
        for i, (mtime, p) in enumerate(entries):
            if i >= KEEP or mtime < cutoff:
                try:
                    os.unlink(p)
                except OSError:
                    pass
    except OSError:
        pass


def snapshot(path, directory):
    """Validate `path` and return the path of a private copy, or None."""
    ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
    if ext not in ("png", "jpg", "jpeg", "gif", "webp"):
        return None
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY | os.O_CLOEXEC
    try:
        fd = os.open(path, flags)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size < 32 or st.st_size > MAX_BYTES:
            return None
        data = b""
        while len(data) <= MAX_BYTES:
            chunk = os.read(fd, 1 << 16)
            if not chunk:
                break
            data += chunk
    except OSError:
        return None
    finally:
        os.close(fd)
    if len(data) < 32 or len(data) > MAX_BYTES or not magic_ok(ext, data[:16]):
        return None
    if ext == "png" and not png_ok(data):
        return None
    name = hashlib.sha256(data).hexdigest()[:40] + "." + ("jpg" if ext == "jpeg" else ext)
    target = os.path.join(directory, name)
    try:
        if os.path.lexists(target):
            os.utime(target, follow_symlinks=False)
            return target
        tmp = os.path.join(directory, ".tmp-%d-%s" % (os.getpid(), name))
        tfd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            os.write(tfd, data) if len(data) < (1 << 16) else _write_all(tfd, data)
        finally:
            os.close(tfd)
        os.rename(tmp, target)
        return target
    except OSError:
        return None


def _write_all(fd, data):
    view = memoryview(data)
    while view:
        n = os.write(fd, view)
        view = view[n:]


def main():
    try:
        wanted = int(sys.argv[1])
    except (IndexError, ValueError):
        wanted = 0
    directory = cache_dir() if wanted > 0 else None
    if directory:
        prune(directory)
    shown = 0
    out = sys.stdout
    for line in sys.stdin:
        if line.startswith("CAND\t"):
            if directory and shown < wanted:
                path = line[5:].rstrip("\n")
                snap = snapshot(path, directory) if path else None
                if snap:
                    shown += 1
                    out.write("THUMB\t" + snap + "\n")
            continue
        out.write(line)
    out.flush()


if __name__ == "__main__":
    main()
