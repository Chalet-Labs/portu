#!/usr/bin/env python3

import os
import sys
import time


target_size = 2 * 1024 * 1024
chunk = b"E" * (64 * 1024)
written = 0
deadline = time.monotonic() + 2
os.set_blocking(sys.stderr.fileno(), False)

while written < target_size:
    try:
        written += os.write(sys.stderr.fileno(), chunk[: target_size - written])
    except BlockingIOError:
        if time.monotonic() >= deadline:
            print("stderr-blocked-before-exit")
            raise SystemExit(75)
        time.sleep(0.001)

print("stdout-complete")
