"""Instance-method cache retains self workload.

The cache wrapper is a module global function object. Because the cached method
key contains ``self``, each temporary worker instance remains reachable through
the unbounded cache after the local variable is dropped.
"""

from functools import lru_cache


class CachedWorker:
    def __init__(self, worker_id):
        self.worker_id = worker_id
        self.payload = "method-cache-self" * 256

    @lru_cache(maxsize=None)
    def render(self, index):
        return {
            "worker_id": self.worker_id,
            "index": index,
            "payload": self.payload + str(index),
        }


def setup():
    CachedWorker.render.cache_clear()


def run_workload(iterations):
    for index in range(iterations):
        worker = CachedWorker(index)
        worker.render(index)
    return {
        "cache_info": CachedWorker.render.cache_info()._asdict(),
    }


if __name__ == "__main__":
    print(run_workload(2000))
