"""weakref.finalize misuse keeps objects alive by storing bound methods."""

import weakref


FINALIZERS = []


class Session:
    def __init__(self, index):
        self.index = index
        self.payload = "weakref-finalize-session" * 256

    def cleanup(self):
        return self.index


def setup():
    FINALIZERS.clear()


def run_workload(iterations):
    for index in range(iterations):
        session = Session(index)
        FINALIZERS.append(weakref.finalize(session, session.cleanup))
    return {
        "finalizers": len(FINALIZERS),
    }


if __name__ == "__main__":
    print(run_workload(2000))
