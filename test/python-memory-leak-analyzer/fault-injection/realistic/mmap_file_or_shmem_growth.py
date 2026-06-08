"""Live PID scenario: file or shared-memory mappings grow and are retained."""

from __future__ import annotations

import argparse
import mmap
import os
import signal
import tempfile
import time


MAPPINGS = []
FILES = []
RUNNING = True
CHUNK_SIZE = 512 * 1024


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    while MAPPINGS:
        mapping = MAPPINGS.pop()
        try:
            mapping.close()
        except OSError:
            pass
    while FILES:
        handle, path = FILES.pop()
        try:
            handle.close()
        except OSError:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass


def _base_dir():
    return "/dev/shm" if os.path.isdir("/dev/shm") and os.access("/dev/shm", os.W_OK) else tempfile.gettempdir()


def run_workload(iterations):
    for _ in range(iterations):
        handle = tempfile.NamedTemporaryFile(prefix="py-mmap-growth-", dir=_base_dir(), delete=False)
        path = handle.name
        handle.truncate(CHUNK_SIZE)
        mapping = mmap.mmap(handle.fileno(), CHUNK_SIZE)
        mapping.write(b"M" * CHUNK_SIZE)
        MAPPINGS.append(mapping)
        FILES.append((handle, path))
    return {"mappings": len(MAPPINGS), "mapped_bytes": len(MAPPINGS) * CHUNK_SIZE}


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    while RUNNING:
        run_workload(batch)
        time.sleep(sleep_seconds)
    print({"mappings": len(MAPPINGS), "mapped_bytes": len(MAPPINGS) * CHUNK_SIZE}, flush=True)
    setup()


def main():
    parser = argparse.ArgumentParser(description="mmap file/shmem retained mapping scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived process for /proc observation.")
    parser.add_argument("--batch", type=int, default=1)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=12)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))
        setup()


if __name__ == "__main__":
    main()
