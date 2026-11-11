"""Read the clipboard as plain text, with a byte cap and a total deadline.

    python3 -I paste.py <max bytes> <seconds>

Qt reads the clipboard synchronously on the shell's own thread and appends
whatever the serving client sends for as long as it keeps sending, so a
client that never closes the transfer, or sends gigabytes, freezes or
exhausts the whole desktop shell. The text fields in this plugin therefore do
not paste natively; they ask for this instead.

`wl-paste` runs in its own session so the whole thing can be stopped at once.
Reading stops at <max bytes> or at the deadline, whichever comes first, the
group is killed and reaped, and whatever arrived is printed with control
characters turned into spaces and invalid UTF-8 dropped. Nothing arriving, or
anything failing, prints nothing.
"""

import os
import select
import signal
import subprocess
import sys
import time


def main():
    try:
        cap = max(1, int(sys.argv[1]))
        deadline = time.monotonic() + max(0.2, float(sys.argv[2]))
    except (IndexError, ValueError):
        return
    try:
        proc = subprocess.Popen(
            ["/usr/bin/wl-paste", "--no-newline", "--type", "text/plain"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            start_new_session=True, close_fds=True,
        )
    except OSError:
        return
    data = b""
    try:
        fd = proc.stdout.fileno()
        while len(data) < cap:
            left = deadline - time.monotonic()
            if left <= 0:
                break
            ready, _, _ = select.select([fd], [], [], left)
            if not ready:
                break
            chunk = os.read(fd, min(4096, cap - len(data)))
            if not chunk:
                break
            data += chunk
    except OSError:
        pass
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        try:
            proc.stdout.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=1)
        except Exception:
            pass
    text = data.decode("utf-8", "ignore")
    text = "".join(" " if (ord(c) < 32 or ord(c) == 127) else c for c in text)
    sys.stdout.write(text)
    sys.stdout.flush()


if __name__ == "__main__":
    main()
