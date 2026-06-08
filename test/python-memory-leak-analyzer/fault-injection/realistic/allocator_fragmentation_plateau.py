"""Live PID scenario: high-water RSS after allocate/free cycles without retained objects."""

from __future__ import annotations

import argparse
import gc
import os
import signal
import time


RUNNING = True
WARMED = False


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    global WARMED
    WARMED = False
    gc.collect()


def run_workload(iterations):
    global WARMED
    for _ in range(iterations):
        batch = [bytearray(256 * 1024) for _ in range(16)]
        for item in batch:
            item[0] = 1
        del batch
    gc.collect()
    WARMED = True
    return {"warmed": WARMED, "retained_payloads": 0}


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    run_workload(batch)
    while RUNNING:
        gc.collect()
        time.sleep(sleep_seconds)
    print({"warmed": WARMED, "retained_payloads": 0}, flush=True)


def main():
    parser = argparse.ArgumentParser(description="allocator high-water plateau scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived process for /proc observation.")
    parser.add_argument("--batch", type=int, default=20)
    parser.add_argument("--sleep", type=float, default=0.1)
    parser.add_argument("--iterations", type=int, default=40)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))


if __name__ == "__main__":
    main()
