"""Reproducible scenario: large transient copy volume is released by final checkpoint."""

from __future__ import annotations

import argparse
import gc
import os
import signal
import time


RUNNING = True
LAST_RESULT = None


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    global LAST_RESULT
    LAST_RESULT = None
    gc.collect()


def run_workload(iterations):
    global LAST_RESULT
    for index in range(iterations):
        left = bytearray(128 * 1024)
        right = bytes(left)
        joined = right + b"x"
        if index % max(1, iterations // 10 or 1) == 0:
            LAST_RESULT = len(joined)
        del left, right, joined
    gc.collect()
    return {"last_result": LAST_RESULT, "retained_payloads": 0}


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    while RUNNING:
        run_workload(batch)
        time.sleep(sleep_seconds)
    print({"last_result": LAST_RESULT, "retained_payloads": 0}, flush=True)


def main():
    parser = argparse.ArgumentParser(description="transient peak copy volume scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived process for /proc observation.")
    parser.add_argument("--batch", type=int, default=50)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=800)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))


if __name__ == "__main__":
    main()
