"""Reference cycles with finalizers are retained through gc.garbage."""

import gc


LEAK_ROOTS = []


class FinalizedNode:
    def __init__(self, index):
        self.index = index
        self.payload = "cycle-finalizer" * 256
        self.peer = None

    def __del__(self):
        pass


def setup():
    LEAK_ROOTS.clear()
    gc.garbage.clear()
    gc.set_debug(gc.DEBUG_SAVEALL)


def run_workload(iterations):
    for index in range(iterations):
        left = FinalizedNode(index)
        right = FinalizedNode(index + iterations)
        left.peer = right
        right.peer = left
        if index % 50 == 0:
            LEAK_ROOTS.append({"sample": left.index})
    collected = gc.collect()
    return {
        "gc_debug_saveall": True,
        "gc_collected": collected,
        "gc_garbage_len": len(gc.garbage),
        "distractor_global_len": len(LEAK_ROOTS),
    }


if __name__ == "__main__":
    print(run_workload(1000))
