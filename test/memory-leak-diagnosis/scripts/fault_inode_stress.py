#!/usr/bin/env python3
"""
fault_inode_stress.py — inode_cache / dentry 缓存压力模拟器 (Branch D2)
反复创建和删除大量文件，观察 dentry/inode_cache slab 增长
部分文件故意不删除以产生 dentry 泄漏

Usage: python3 fault_inode_stress.py [files_per_sec] [leak_ratio] [duration_sec]
Default: 100 files/sec, 0.1 (10% leaked), 60 seconds
"""
import os
import sys
import time
import signal
import tempfile
import shutil

running = True

def handler(signum, frame):
    global running
    running = False

signal.signal(signal.SIGINT, handler)
signal.signal(signal.SIGTERM, handler)

FILES_PER_SEC = int(sys.argv[1]) if len(sys.argv) > 1 else 100
LEAK_RATIO = float(sys.argv[2]) if len(sys.argv) > 2 else 0.1
DURATION = int(sys.argv[3]) if len(sys.argv) > 3 else 60

pid = os.getpid()
tmpdir = tempfile.mkdtemp(prefix="inode_stress_")
leakdir = os.path.join(tmpdir, "leaked")
os.makedirs(leakdir, exist_ok=True)

print(f"[fault_inode_stress] PID={pid}, {FILES_PER_SEC} files/s, "
      f"leak ratio={LEAK_RATIO}, duration={DURATION}s")
print(f"  Work dir: {tmpdir}")

iter_count = 0
created = 0
leaked = 0
deleted = 0

try:
    while running:
        batch_start = time.time()
        for i in range(FILES_PER_SEC):
            fname = f"file_{iter_count}_{i}.txt"
            # Create file
            with open(os.path.join(tmpdir, fname), 'w') as f:
                f.write('x' * 4096)

            if iter_count % 10 == 0 and i < int(FILES_PER_SEC * LEAK_RATIO):
                # Leak some files (don't delete)
                shutil.copy(
                    os.path.join(tmpdir, fname),
                    os.path.join(leakdir, f"leaked_{iter_count}_{i}.txt")
                )
                leaked += 1
            else:
                # Delete immediately to stress dentry/inode
                os.unlink(os.path.join(tmpdir, fname))
                deleted += 1

            created += 1

        iter_count += 1

        # Report slab info
        if iter_count % 5 == 0:
            try:
                with open("/proc/slabinfo") as f:
                    for line in f:
                        if line.startswith("dentry") or line.startswith("inode_cache"):
                            print(f"  [{iter_count}] {line.strip()[:80]}")
            except:
                pass
            print(f"  Created={created}, Deleted={deleted}, Leaked={leaked}")

        if DURATION > 0 and iter_count >= DURATION:
            break

        # Maintain rate
        elapsed = time.time() - batch_start
        if elapsed < 1.0:
            time.sleep(1.0 - elapsed)

except KeyboardInterrupt:
    pass

print(f"\n[fault_inode_stress] Done. Created={created}, Leaked={leaked}")
print(f"  Leaked files in: {leakdir}")
print(f"  Check slab: grep -E 'dentry|inode' /proc/slabinfo")
running = False
# Keep leaked files until container exits
time.sleep(3600)
