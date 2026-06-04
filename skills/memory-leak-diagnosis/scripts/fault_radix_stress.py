#!/usr/bin/env python3
"""
fault_radix_stress.py — radix_tree_node / 页缓存索引节点压力模拟器 (Branch D4)
反复 mmap/munmap 文件来操作页缓存，制造 radix_tree_node 压力

Usage: python3 fault_radix_stress.py [ops_per_sec] [duration_sec]
Default: 50 ops/sec, 60 seconds
"""
import os
import sys
import time
import signal
import mmap
import tempfile

running = True

def handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)

OPS_PER_SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 50
DURATION = int(sys.argv[2]) if len(sys.argv) > 2 else 60

pid = os.getpid()
tmpdir = tempfile.mkdtemp(prefix="radix_stress_")

# Create a large backing file
backing_file = os.path.join(tmpdir, "backing.dat")
with open(backing_file, 'wb') as f:
    f.write(b'\x00' * 10 * 1024 * 1024)  # 10MB

print(f"[fault_radix_stress] PID={pid}, {OPS_PER_SEC} ops/s, {DURATION}s")
print(f"  Backing file: {backing_file} (10MB)")

iter_count = 0
maps = []

try:
    while running:
        batch_start = time.time()

        for i in range(OPS_PER_SEC):
            fd = os.open(backing_file, os.O_RDWR)
            # Map 64KB at random offset
            offset = (iter_count * 65432 + i * 8192) % (9 * 1024 * 1024)
            m = mmap.mmap(fd, 65536, offset=offset,
                          access=mmap.ACCESS_READ)
            # Touch first page to ensure page cache population
            _ = m[0]
            m.close()
            os.close(fd)

            # Every 10th iteration, keep a map alive
            if i % 10 == 0:
                fd2 = os.open(backing_file, os.O_RDWR)
                m2 = mmap.mmap(fd2, 4096,
                               access=mmap.ACCESS_READ)
                maps.append((fd2, m2))

        iter_count += 1

        if iter_count % 10 == 0:
            print(f"[{iter_count}] Active mmaps: {len(maps)}")
            try:
                with open("/proc/slabinfo") as f:
                    for line in f:
                        if "radix_tree" in line:
                            print(f"  radix_tree_node: {line.strip()[:80]}")
            except:
                pass

        if DURATION > 0 and iter_count >= DURATION:
            break

        elapsed = time.time() - batch_start
        if elapsed < 1.0:
            time.sleep(1.0 - elapsed)

except KeyboardInterrupt:
    pass

print(f"\n[fault_radix_stress] Done. {iter_count} iterations, {len(maps)} active maps")

# Cleanup
for fd, m in maps:
    try: m.close()
    except: pass
    try: os.close(fd)
    except: pass

# Keep process alive
time.sleep(3600)
