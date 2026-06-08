"""Thread-local request state accumulates on persistent worker threads."""

import concurrent.futures
import threading


LOCAL_STATE = threading.local()
EXECUTOR = None


def setup():
    global EXECUTOR
    if EXECUTOR is not None:
        EXECUTOR.shutdown(wait=True)
    EXECUTOR = concurrent.futures.ThreadPoolExecutor(max_workers=4)


def _worker(start, count):
    if not hasattr(LOCAL_STATE, "requests"):
        LOCAL_STATE.requests = []
    for offset in range(count):
        index = start + offset
        LOCAL_STATE.requests.append(
            {
                "index": index,
                "payload": "thread-local-request" * 256,
            }
        )
    return len(LOCAL_STATE.requests)


def run_workload(iterations):
    batch = max(1, iterations // 4)
    futures = []
    for worker_id in range(4):
        futures.append(EXECUTOR.submit(_worker, worker_id * batch, batch))
    lengths = [future.result(timeout=10) for future in futures]
    return {
        "worker_local_lengths": lengths,
    }


if __name__ == "__main__":
    setup()
    print(run_workload(2000))
    EXECUTOR.shutdown(wait=True)
