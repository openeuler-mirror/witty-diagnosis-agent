"""Closure cells retain request payloads through a global task table."""


TASK_TABLE = {}


def make_handler(index):
    payload = {
        "index": index,
        "body": "closure-captured-body" * 256,
        "headers": {"request-id": str(index)},
    }

    def handler():
        return payload["index"], len(payload["body"])

    return handler


def setup():
    TASK_TABLE.clear()


def run_workload(iterations):
    for index in range(iterations):
        TASK_TABLE[f"request-{index}"] = make_handler(index)
    return {
        "task_count": len(TASK_TABLE),
    }


if __name__ == "__main__":
    print(run_workload(2000))
