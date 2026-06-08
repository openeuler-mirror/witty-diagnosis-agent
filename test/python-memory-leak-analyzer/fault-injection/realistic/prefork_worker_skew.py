"""Live PID scenario: stable master process with a leaking worker child."""

from __future__ import annotations

import argparse
import multiprocessing as mp
import os
import signal
import time


RUNNING = True
MASTER_STATE = []


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    MASTER_STATE.clear()


def run_workload(iterations):
    MASTER_STATE.extend({"master": index} for index in range(min(iterations, 5)))
    return {"master_state_len": len(MASTER_STATE)}


def worker_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    bucket = []
    while RUNNING:
        for index in range(batch):
            bucket.append({"index": index, "payload": "worker-skew" * 512})
        time.sleep(sleep_seconds)


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    child = mp.Process(target=worker_loop, args=(batch, sleep_seconds), daemon=False)
    child.start()
    print(f"pid={os.getpid()} child={child.pid}", flush=True)
    try:
        while RUNNING and child.is_alive():
            time.sleep(0.2)
    finally:
        if child.is_alive():
            child.terminate()
            child.join(timeout=3)
        if child.is_alive():
            child.kill()
    print({"master_state_len": len(MASTER_STATE), "child_pid": child.pid}, flush=True)


def main():
    parser = argparse.ArgumentParser(description="prefork worker skew memory growth scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived master PID for /proc observation.")
    parser.add_argument("--batch", type=int, default=80)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=200)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))


if __name__ == "__main__":
    main()
