"""Long-running process used for read-only PID observation tests."""

import os
import signal
import sys
import time


LIVE_BUCKET = []
RUNNING = True


def _stop(_signum, _frame):
    global RUNNING
    RUNNING = False


def setup():
    LIVE_BUCKET.clear()


def run_workload(iterations):
    for index in range(iterations):
        LIVE_BUCKET.append(
            {
                "index": index,
                "payload": "live-pid-readonly" * 512,
            }
        )
    return {
        "live_bucket_len": len(LIVE_BUCKET),
    }


def main():
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    print(f"pid={os.getpid()}", flush=True)
    index = 0
    while RUNNING:
        LIVE_BUCKET.append(
            {
                "index": index,
                "payload": "live-pid-readonly" * 512,
            }
        )
        index += 1
        time.sleep(0.02)
    print({"live_bucket_len": len(LIVE_BUCKET)}, flush=True)


if __name__ == "__main__":
    main()
