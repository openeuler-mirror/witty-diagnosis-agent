"""Unbounded lru_cache workload for python-memory-leak-analyzer tests."""

from functools import lru_cache


@lru_cache(maxsize=None)
def cached_payload(index):
    return "cache-payload-%08d-" % index + ("x" * 2048)


def setup():
    cached_payload.cache_clear()


def run_workload(iterations):
    for index in range(iterations):
        cached_payload(index)
    return cached_payload.cache_info()._asdict()


if __name__ == "__main__":
    print(run_workload(20000))
