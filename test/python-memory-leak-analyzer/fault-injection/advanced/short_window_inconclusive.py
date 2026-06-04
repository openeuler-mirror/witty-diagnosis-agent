"""Short-window warm-up workload that should not be overcalled as a leak."""


WARM_CACHE = {}
MAX_CACHE_SIZE = 128


def setup():
    WARM_CACHE.clear()


def run_workload(iterations):
    for index in range(iterations):
        key = index % MAX_CACHE_SIZE
        WARM_CACHE.setdefault(
            key,
            {
                "key": key,
                "payload": "bounded-warm-cache" * 128,
            },
        )
    return {
        "cache_len": len(WARM_CACHE),
        "max_cache_size": MAX_CACHE_SIZE,
    }


if __name__ == "__main__":
    print(run_workload(2000))
