"""RSS growth / allocator pressure workload with weak Python-object attribution.

This workload allocates and drops many bytearrays. It can raise RSS or high-water
memory in some allocators even though the Python-level containers are not retained.
It is intended as a pseudo-fragmentation / non-leak contrast scenario.
"""


def setup():
    pass


def run_workload(iterations):
    for _ in range(iterations):
        chunks = [bytearray(64 * 1024) for _ in range(32)]
        for chunk in chunks:
            chunk[0] = 1
        del chunks
    return {"iterations": iterations, "retained": 0}


if __name__ == "__main__":
    print(run_workload(200))
