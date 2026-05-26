#!/usr/bin/env python3
"""
fault_shm_eacces.py -- inject shared memory permission denied fault
Root creates SHM with perms=000 (no access), then non-root user
tries to attach, triggering EACCES.
"""
import ctypes
import os
import time
import subprocess

libc = ctypes.CDLL("libc.so.6")
IPC_CREAT = 0o1000
IPC_EXCL = 0o2000
IPC_RMID = 0
KEY = 0x12345679

# Cleanup any old shm
old = libc.shmget(KEY, 4096, 0)
if old >= 0:
    libc.shmctl(old, IPC_RMID, 0)

# Create shm with perms 000 (nobody can access without CAP_IPC_OWNER)
shmid = libc.shmget(KEY, 4096, IPC_CREAT | IPC_EXCL | 0o000)
print(f"[FAULT] root created shmid={shmid} perms=000", flush=True)

# Verify root can still attach (CAP_IPC_OWNER bypass)
addr = libc.shmat(shmid, None, 0)
if addr != -1:
    print(f"[FAULT] root shmat OK (CAP_IPC_OWNER bypass)", flush=True)
    libc.shmdt(addr)

# Now test non-root attach via su
result = subprocess.run(
    ["su", "-s", "/bin/sh", "nobody", "-c",
     'python3 -c "import ctypes,os; libc=ctypes.CDLL(os.environ[\"libc.so.6\"]); KEY=0x12345679; shmid=libc.shmget(KEY,4096,0); print(\"shmid=\"+str(shmid)); addr=libc.shmat(shmid,None,0); f=\"OK\" if addr!=-1 else f\"EACCES errno={ctypes.get_errno()}\"; print(f)"'],
    capture_output=True, text=True, timeout=10
)
output = result.stdout.strip() if result.stdout else ""
error = result.stderr.strip() if result.stderr else ""
print(f"[FAULT] nobody shmat result: {output}", flush=True)
if error:
    print(f"[FAULT] stderr: {error}", flush=True)

print(f"[FAULT] SHM perms=000 created, pausing for diagnostics...", flush=True)
print(f"[FAULT] ipcs can show: ipcs -m -i {shmid}", flush=True)
time.sleep(3600)
