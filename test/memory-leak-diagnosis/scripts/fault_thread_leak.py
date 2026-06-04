#!/usr/bin/env python3
"""
fault_thread_leak.py — Thread leak simulator (Branch A3)
Creates threads that allocate memory and never clean up.
Usage: python3 fault_thread_leak.py [threads_per_sec] [mb_per_thread] [duration_sec]
"""
import os
import sys
import time
import signal
import threading

running = True

def handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)

THREADS_PER_SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 2
MB_PER_THREAD = int(sys.argv[2]) if len(sys.argv) > 2 else 5
DURATION = int(sys.argv[3]) if len(sys.argv) > 3 else 0

pid = os.getpid()
threads = []
lock = threading.Lock()

def thread_worker(tid):
    """Each thread allocates memory and holds it."""
    chunk = bytearray(MB_PER_THREAD * 1024 * 1024)
    # Touch pages
    for i in range(0, len(chunk), 4096):
        chunk[i] = tid & 0xFF
    # Thread stays alive holding the memory
    while running:
        time.sleep(1)

print(f"[fault_thread_leak] PID={pid} creating {THREADS_PER_SEC} threads/sec "
      f"each leaking {MB_PER_THREAD} MB")

start = time.time()
iter_count = 0

try:
    while running:
        for t in range(THREADS_PER_SEC):
            t = threading.Thread(target=thread_worker, args=(iter_count,), daemon=True)
            t.start()
            threads.append(t)
        iter_count += 1

        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    rss = line.split()[1]
                elif line.startswith("Threads:"):
                    thr = line.split()[1]

        elapsed = time.time() - start
        print(f"[{iter_count}] t={elapsed:.0f}s RSS={rss} kB threads={thr} "
              f"created={len(threads)}")
        sys.stdout.flush()

        if DURATION > 0 and iter_count >= DURATION:
            break
        time.sleep(1)
except MemoryError:
    print(f"[fault_thread_leak] Out of memory")
except KeyboardInterrupt:
    pass

print(f"[fault_thread_leak] Done. Created {len(threads)} threads.")
