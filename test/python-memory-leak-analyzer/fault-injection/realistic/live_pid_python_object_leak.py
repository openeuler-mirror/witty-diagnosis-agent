"""Live PID scenario: Python retained objects grow in a global container."""

from __future__ import annotations

import argparse
import os
import signal
import time


LEAK_BUCKET = []
RUNNING = True


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    LEAK_BUCKET.clear()


def run_workload(iterations):
    for index in range(iterations):
        LEAK_BUCKET.append(
            {
                "index": index,
                "payload": ("python-retained-leak-%06d" % index) * 128,
                "tags": [index, index + 1, index + 2],
            }
        )
    return {"leak_bucket_len": len(LEAK_BUCKET)}


def live_loop(batch: int, sleep_seconds: float):
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    while RUNNING:
        run_workload(batch)
        time.sleep(sleep_seconds)
    print({"leak_bucket_len": len(LEAK_BUCKET)}, flush=True)


def main():
    parser = argparse.ArgumentParser(description="Python object retained leak production-style scenario.")
    parser.add_argument("--live", action="store_true", help="Run as a long-lived process for /proc observation.")
    parser.add_argument("--batch", type=int, default=80)
    parser.add_argument("--sleep", type=float, default=0.05)
    parser.add_argument("--iterations", type=int, default=800)
    args = parser.parse_args()
    if args.live:
        live_loop(args.batch, args.sleep)
    else:
        print(run_workload(args.iterations))


if __name__ == "__main__":
    main()
