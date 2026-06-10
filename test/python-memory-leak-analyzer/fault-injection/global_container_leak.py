"""Global container leak workload for python-memory-leak-analyzer tests."""

LEAK_BUCKET = []


def setup():
    LEAK_BUCKET.clear()


def run_workload(iterations):
    for index in range(iterations):
        LEAK_BUCKET.append(
            {
                "index": index,
                "payload": "global-container-leak" * 128,
                "tags": [index, index + 1, index + 2],
            }
        )
    return {"leak_bucket_len": len(LEAK_BUCKET)}


if __name__ == "__main__":
    print(run_workload(20000))
