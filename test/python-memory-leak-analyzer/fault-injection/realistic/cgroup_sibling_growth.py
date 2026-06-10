"""Live PID scenario: watched target stays stable while another same-cgroup process grows."""

from __future__ import annotations

import argparse
import os
import signal
import time


RUNNING = True
PARENT_STATE = []


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    PARENT_STATE.clear()


def run_workload(iterations):
    PARENT_STATE.extend(range(min(iterations, 3)))
    return {"parent_state_len": len(PARENT_STATE)}


def sibling_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    bucket = []
    print(f"sibling_pid={os.getpid()}", flush=True)
    while RUNNING:
        for index in range(batch):
            bucket.append({"index": index, "payload": "cgroup-sibling" * 512})
        time.sleep(sleep_seconds)


def live_loop(sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    while RUNNING:
        time.sleep(sleep_seconds)
    print({"parent_state_len": len(PARENT_STATE)}, flush=True)


def main():
    parser = argparse.ArgumentParser(description="cgroup sibling growth scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a stable target PID for /proc observation.")
    parser.add_argument("--sibling", action="store_true", help="Run the independent same-cgroup growing sibling process.")
    parser.add_argument("--batch", type=int, default=80)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=200)
    args = parser.parse_args()
    if args.sibling:
        sibling_loop(args.batch, args.sleep)
    elif args.live:
        live_loop(args.sleep)
    else:
        print(run_workload(args.iterations))


if __name__ == "__main__":
    main()
