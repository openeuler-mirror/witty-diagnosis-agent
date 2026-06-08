"""Unclosed generators retain frame locals and large payloads."""


OPEN_GENERATORS = []


def stream_records(index):
    payload = {
        "index": index,
        "chunk": "unclosed-generator-frame" * 256,
    }
    yield payload["index"]
    yield len(payload["chunk"])


def setup():
    OPEN_GENERATORS.clear()


def run_workload(iterations):
    for index in range(iterations):
        generator = stream_records(index)
        next(generator)
        OPEN_GENERATORS.append(generator)
    return {
        "open_generators": len(OPEN_GENERATORS),
    }


if __name__ == "__main__":
    print(run_workload(2000))
