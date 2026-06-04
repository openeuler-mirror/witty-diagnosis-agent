#!/usr/bin/env python3
"""
fault_fd_leak.py — File descriptor leak simulator (Branch A4 companion)
Opens files/closes them but holds some descriptors.
Usage: python3 fault_fd_leak.py [open_per_sec] [hold_count]
"""
import os
import sys
import time
import signal

running = True

def handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)

OPEN_PER_SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 10
HOLD_COUNT = int(sys.argv[2]) if len(sys.argv) > 2 else 100

pid = os.getpid()
held_fds = []
tmpdir = "/tmp/fault_fd_leak"
os.makedirs(tmpdir, exist_ok=True)

print(f"[fault_fd_leak] PID={pid} opening {OPEN_PER_SEC} fds/sec, holding {HOLD_COUNT}")

iter_count = 0
try:
    while running:
        for _ in range(OPEN_PER_SEC):
            fd_path = f"{tmpdir}/fault_fd_{iter_count}_{_}.tmp"
            with open(fd_path, 'w') as f:
                f.write("x" * 4096)
            # Hold some fds, release others
            if len(held_fds) < HOLD_COUNT:
                fd = os.open(fd_path, os.O_RDONLY)
                held_fds.append(fd)
            else:
                # Release oldest and open new
                old = held_fds.pop(0)
                os.close(old)
                fd = os.open(fd_path, os.O_RDONLY)
                held_fds.append(fd)

        iter_count += 1
        fd_count = len(os.listdir(f"/proc/{pid}/fd"))
        print(f"[{iter_count}] fds={fd_count} held={len(held_fds)}")
        sys.stdout.flush()
        time.sleep(1)
except KeyboardInterrupt:
    pass

# Cleanup
for fd in held_fds:
    try: os.close(fd)
    except: pass
print(f"[fault_fd_leak] Done.")
