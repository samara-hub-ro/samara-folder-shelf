"""Read the clipboard as plain text, with a byte cap and a total deadline.

    python3 -I paste.py <max bytes> <seconds>

Qt reads the clipboard synchronously on the shell's own thread and appends
whatever the serving client sends for as long as it keeps sending, so a
client that never closes the transfer, or sends gigabytes, freezes or
exhausts the whole desktop shell. The text fields in this plugin therefore do
not paste natively; they ask for this instead.

`wl-paste` runs under `timeout` in its own session, so the whole group can be
stopped at once: by this helper when it is done or is told to stop (SIGTERM
kills the group), and by `timeout` itself if this helper is killed outright.
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
        deadline_s = max(0.2, float(sys.argv[2]))
        deadline = time.monotonic() + deadline_s
    except (IndexError, ValueError):
        return
    try:
        # `timeout` is the independent bound: it owns the session's group
        # (wl-paste and the cat it forks) and ends it at the deadline even if
        # this process is killed before it can clean up.
        proc = subprocess.Popen(
            ["/usr/bin/timeout", "-k", "1", str(int(deadline_s) + 1),
             "/usr/bin/wl-paste", "--no-newline", "--type", "text/plain"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            start_new_session=True, close_fds=True,
        )
    except OSError:
        return
    def stop(*_):
        # Cancellation arrives as SIGTERM: take the whole group down, then go.
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        os._exit(1)

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, stop)
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
