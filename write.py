"""Replace one file atomically without following a symlink anywhere on the way.

    python3 -I write.py <absolute path> <byte limit>   < new contents

QML can write a file only through FileView, which resolves the path it is
given like any other open: a symlink at the file, or at any directory above
it, sends the write somewhere else. The shelf file's location is a setting,
so its path is not ours to trust. This does the write from a directory
descriptor instead:

  1. Walk the path from `/` one component at a time with
     `openat(O_DIRECTORY | O_NOFOLLOW)`, so every directory on the way is the
     real one and not a link to another. Missing directories at the end of
     the path are created 0700 as the walk reaches them.
  2. Every directory on the way must belong to root or to us, and any that
     others can write to must be sticky, so nobody else can swap a component
     out from under the walk. The last one — the directory the file lives in
     — must be ours and writable by nobody else.
  3. Whatever is at the file's name now, looked at without following it,
     must be a regular file of ours, or nothing.
  4. The contents go to a fresh temporary created in that directory with
     `O_CREAT | O_EXCL | O_NOFOLLOW`, are synced, and are renamed over the
     name relative to the same descriptor. The rename replaces a directory
     entry; it never follows one. Then the directory itself is synced.

The contents come in on stdin, never argv, and must be valid JSON no larger
than the limit. Any refusal is one line on stderr and a non-zero exit; the
file is then exactly as it was.
"""

import json
import os
import secrets
import stat
import sys


def fail(message):
    sys.stderr.write("folder-shelf write: " + message + "\n")
    sys.exit(1)


def check_directory(fd, where, last):
    st = os.fstat(fd)
    uid = os.getuid()
    if last:
        if st.st_uid != uid:
            fail(where + ": the directory holding the file is not ours")
        if st.st_mode & 0o022:
            fail(where + ": the directory holding the file is writable by others")
        return
    if st.st_uid not in (0, uid):
        fail(where + ": owned by uid " + str(st.st_uid))
    if st.st_mode & 0o022 and not st.st_mode & stat.S_ISVTX:
        fail(where + ": writable by others and not sticky")


def open_parent(parts):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open("/", flags)
    check_directory(fd, "/", len(parts) == 0)
    where = ""
    for i, name in enumerate(parts):
        where += "/" + name
        try:
            nxt = os.open(name, flags, dir_fd=fd)
        except FileNotFoundError:
            try:
                os.mkdir(name, 0o700, dir_fd=fd)
            except FileExistsError:
                pass
            nxt = os.open(name, flags, dir_fd=fd)
        except OSError as e:
            # ELOOP or ENOTDIR: a symlink, or not a directory at all.
            fail(where + ": not a plain directory (" + e.strerror + ")")
        os.close(fd)
        fd = nxt
        check_directory(fd, where, i == len(parts) - 1)
    return fd


def main():
    if len(sys.argv) != 3:
        fail("usage: write.py <absolute path> <byte limit>")
    path, limit = sys.argv[1], int(sys.argv[2])

    if not path.startswith("/"):
        fail(path + ": not an absolute path")
    parts = path.split("/")[1:]
    if any(p in ("", ".", "..") for p in parts):
        fail(path + ": not a plain path")
    parent, name = parts[:-1], parts[-1]

    data = sys.stdin.buffer.read(limit + 1)
    if len(data) > limit:
        fail(path + ": new contents are larger than " + str(limit) + " bytes")
    try:
        json.loads(data)
    except ValueError:
        fail(path + ": new contents are not valid JSON")

    dfd = open_parent(parent)

    mode = 0o600
    try:
        st = os.stat(name, dir_fd=dfd, follow_symlinks=False)
    except FileNotFoundError:
        st = None
    if st is not None:
        if not stat.S_ISREG(st.st_mode):
            fail(path + ": exists and is not a regular file")
        if st.st_uid != os.getuid():
            fail(path + ": exists and is not ours")
        mode = stat.S_IMODE(st.st_mode) & 0o644

    temp = "." + name + "." + secrets.token_hex(6) + ".tmp"
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                 0o600, dir_fd=dfd)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fchmod(fd, mode)
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.rename(temp, name, src_dir_fd=dfd, dst_dir_fd=dfd)
    except BaseException:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temp, dir_fd=dfd)
        except OSError:
            pass
        raise
    os.fsync(dfd)
    os.close(dfd)


if __name__ == "__main__":
    try:
        main()
    except OSError as e:
        fail(str(e))
