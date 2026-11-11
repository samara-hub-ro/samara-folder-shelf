"""List the sub-folders of one folder for the picker, with hard bounds.

    python3 -I listdirs.py <folder> <max rows> <seconds>

Writes each folder name followed by a NUL, at most <max rows> of them, and
stops at the deadline. A name with a control character in it is skipped: the
picker shows names as text and navigates by them, and one that cannot be
written on a line cannot be told apart from two. A folder that cannot be
read prints nothing and exits 0, which the picker draws as "No folders in
here".

Bounded on purpose. The previous listing ran bash, find and sort with an
unbounded collector on the other end; a directory with millions of entries
meant a pipeline nobody owned and an unbounded string in the shell. This is
one process, one pass, and it is run under `timeout`, so stopping it stops
everything.
"""

import os
import sys
import time


def main():
    try:
        folder = sys.argv[1]
        cap = max(1, int(sys.argv[2]))
        deadline = time.monotonic() + max(0.2, float(sys.argv[3]))
    except (IndexError, ValueError):
        return
    names = []
    try:
        with os.scandir(folder) as it:
            for entry in it:
                if time.monotonic() > deadline or len(names) >= cap:
                    break
                name = entry.name
                if len(name) > 255 or any(ord(c) < 32 or ord(c) == 127 for c in name):
                    continue
                try:
                    if entry.is_dir():
                        names.append(name)
                except OSError:
                    continue
    except OSError:
        return
    names.sort(key=lambda n: (n.casefold(), n))
    out = sys.stdout.buffer
    for name in names:
        out.write(os.fsencode(name) + b"\0")
    out.flush()


if __name__ == "__main__":
    main()
