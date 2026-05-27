#!/usr/bin/env python3
"""fault_reclaim_mem.py -- Trigger memory reclaim by allocating ~80% of RAM"""
import mmap, os, time, sys

addrs = []
total_mb = 0
target_mb = 12000  # 12GB out of ~16GB

print("[FAULT] PID=%d  Allocating up to %d MB..." % (os.getpid(), target_mb), flush=True)

try:
    for i in range(target_mb):
        m = mmap.mmap(-1, 1024*1024, prot=mmap.PROT_READ|mmap.PROT_WRITE)
        m[0] = 0
        addrs.append(m)
        total_mb += 1
        if total_mb % 1000 == 0:
            print("[FAULT] Allocated %d MB" % total_mb, flush=True)
except Exception as e:
    print("[FAULT] Allocation stopped at %d MB: %s" % (total_mb, e), flush=True)

print("[FAULT] Total allocated: %d MB" % total_mb, flush=True)

# Show reclaim stats
with open("/proc/vmstat") as f:
    for line in f:
        if "allocstall" in line or "pgscan" in line:
            print("[FAULT] " + line.strip(), flush=True)

# Show meminfo
with open("/proc/meminfo") as f:
    for line in f:
        if "MemFree" in line or "MemAvailable" in line or "Cached" in line or "Dirty" in line:
            print("[FAULT] " + line.strip(), flush=True)

print("[FAULT] Holding for 60s for witty diagnosis...", flush=True)
time.sleep(60)
