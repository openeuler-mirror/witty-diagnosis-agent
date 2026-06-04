#!/usr/bin/env python3
"""
fault_heap_leak_v2.py — Gradual heap leak simulator (Branch A/C)
Leaks memory at a configurable rate with RSS reporting.
Usage: python3 fault_heap_leak_v2.py [MB_per_sec] [duration_sec]
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

MB_PER_SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 10
DURATION = int(sys.argv[2]) if len(sys.argv) > 2 else 0

leak = []
pid = os.getpid()
print(f"[fault_heap_leak_v2] PID={pid} leaking at {MB_PER_SEC} MB/s", end="")
if DURATION > 0:
    print(f" for {DURATION} seconds")
else:
    print()
print(f"[fault_heap_leak_v2] Type: {'aggressive' if MB_PER_SEC >= 50 else 'gradual'} leak")

start = time.time()
iter_count = 0

try:
    while running:
        # Allocate ~MB_PER_SEC MB in one chunk
        chunk = bytearray(MB_PER_SEC * 1024 * 1024)
        leak.append(chunk)  # keep reference to prevent GC
        iter_count += 1

        # Report RSS
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    rss = line.split()[1]
                    peaks = line.split()[1]
                    break

        elapsed = time.time() - start
        rate = (iter_count * MB_PER_SEC) / (elapsed if elapsed > 0 else 1)
        print(f"[{iter_count}] t={elapsed:.0f}s RSS={rss} kB leak_rate={rate:.1f} MB/s")
        sys.stdout.flush()

        if DURATION > 0 and iter_count >= DURATION:
            break
        time.sleep(1)
except MemoryError:
    print(f"[fault_heap_leak_v2] Out of memory at iteration {iter_count}")
except KeyboardInterrupt:
    pass

total_mb = iter_count * MB_PER_SEC
print(f"[fault_heap_leak_v2] Done. Leaked ~{total_mb} MB in {time.time()-start:.0f}s")
