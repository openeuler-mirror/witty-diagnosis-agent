"""Live PID scenario: native memory grows through ctypes malloc while Python heap stays small."""

from __future__ import annotations

import argparse
import ctypes
import os
import signal
import time


LIBC = ctypes.CDLL(None)
LIBC.malloc.argtypes = [ctypes.c_size_t]
LIBC.malloc.restype = ctypes.c_void_p
LIBC.free.argtypes = [ctypes.c_void_p]
LIBC.memset.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_size_t]

POINTERS = []
RUNNING = True
CHUNK_SIZE = 256 * 1024


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    while POINTERS:
        ptr = POINTERS.pop()
        if ptr:
            LIBC.free(ptr)


def run_workload(iterations):
    for _ in range(iterations):
        ptr = LIBC.malloc(CHUNK_SIZE)
        if not ptr:
            raise MemoryError("malloc failed")
        LIBC.memset(ptr, 0x41, CHUNK_SIZE)
        POINTERS.append(ptr)
    return {"native_allocations": len(POINTERS), "native_bytes": len(POINTERS) * CHUNK_SIZE}


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    while RUNNING:
        run_workload(batch)
        time.sleep(sleep_seconds)
    print({"native_allocations": len(POINTERS), "native_bytes": len(POINTERS) * CHUNK_SIZE}, flush=True)
    setup()


def main():
    parser = argparse.ArgumentParser(description="ctypes malloc retained native memory scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived process for /proc observation.")
    parser.add_argument("--batch", type=int, default=2)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=20)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))
        setup()


if __name__ == "__main__":
    main()
