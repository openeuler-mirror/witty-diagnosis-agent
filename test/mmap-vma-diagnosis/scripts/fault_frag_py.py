#!/usr/bin/env python3
"""Address space fragmentation fault injector (Python version)"""
import mmap
import os
import time
import sys

addrs = []
print(f"[FAULT] PID={os.getpid()}", flush=True)
print(f"[FAULT] Creating 8000 small mappings...", flush=True)

for i in range(8000):
    try:
        m = mmap.mmap(-1, 4096, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        addrs.append(m)
    except OSError as e:
        print(f"[FAULT] Fail at {i}: {e}", flush=True)
        break
    if i % 2000 == 0:
        print(f"[FAULT] Created {i} mappings", flush=True)

print(f"[FAULT] All mappings done. Attempting 256MB large mapping...", flush=True)
try:
    large = mmap.mmap(-1, 256 * 1024 * 1024, prot=mmap.PROT_READ | mmap.PROT_WRITE)
    print(f"[FAULT] Large mmap OK", flush=True)
    large.close()
except OSError as e:
    print(f"[FAULT] Large mmap FAILED: {e} - fragmentation confirmed", flush=True)

print(f"[FAULT] Pausing for diagnostics (VMA count high)...", flush=True)
time.sleep(3600)
