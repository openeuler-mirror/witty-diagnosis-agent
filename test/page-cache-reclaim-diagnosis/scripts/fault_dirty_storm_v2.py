#!/usr/bin/env python3
"""fault_dirty_storm_v2.py -- Dirty page writeback storm injector v2
Writes large amount of data, forces dirty page accumulation by disabling
flusher temporarily, then triggers sync to create writeback burst."""
import os
import time
import sys

print("[FAULT] PID=%d  Dirty writeback storm injector v2" % os.getpid(), flush=True)

# Write 2GB data in chunks
chunk = 4 * 1024 * 1024  # 4MB
total = 2 * 1024 * 1024 * 1024  # 2GB
written = 0

f = open("/tmp/fault_dirty_bigfile", "wb")
print("[FAULT] Writing 2GB file (this will accumulate dirty pages)...", flush=True)

t1 = time.time()
while written < total:
    f.write(b"A" * chunk)
    written += chunk
    if written % (256 * 1024 * 1024) == 0:
        mb = written / 1024 / 1024
        # Check dirty state
        with open("/proc/meminfo") as m:
            for line in m:
                if "Dirty" in line or "Writeback" in line or "Cached" in line:
                    if "kB" in line:
                        print("[FAULT] %s after %d MB written" % (line.strip(), mb), flush=True)
        print("[FAULT] Written %d MB" % mb, flush=True)

t2 = time.time()
print("[FAULT] Write done: %d MB in %.1fs (%.0f MB/s)" % (
    total / 1024 / 1024, t2 - t1, (total / 1024 / 1024) / (t2 - t1)), flush=True)

# Check dirty state before fsync
print("[FAULT] === Dirty state BEFORE fsync ===", flush=True)
os.system("grep -E 'Dirty|Writeback|WritebackTmp' /proc/meminfo")
with open("/proc/vmstat") as vm:
    for line in vm:
        if "nr_dirty" in line or "nr_writeback" in line:
            print("[FAULT] " + line.strip(), flush=True)

# Force sync - THIS triggers writeback storm
print("[FAULT] === Forcing fsync (writeback storm) ===", flush=True)
t1 = time.time()
os.fsync(f.fileno())
t2 = time.time()
print("[FAULT] fsync took %.2f seconds" % (t2 - t1), flush=True)

# Check after
print("[FAULT] === Dirty state AFTER fsync ===", flush=True)
os.system("grep -E 'Dirty|Writeback|Cached' /proc/meminfo")

print("[FAULT] Pausing 60s for witty diagnosis...", flush=True)
time.sleep(60)
f.close()
os.unlink("/tmp/fault_dirty_bigfile")
print("[FAULT] Done", flush=True)
