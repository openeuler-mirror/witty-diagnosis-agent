"""Pending asyncio tasks retain coroutine frame locals."""

import asyncio


LOOP = None
PENDING_TASKS = []


async def hold_payload(index):
    payload = {
        "index": index,
        "body": "asyncio-pending-task" * 256,
    }
    await asyncio.Event().wait()
    return payload


def setup():
    global LOOP
    for task in PENDING_TASKS:
        task.cancel()
    PENDING_TASKS.clear()
    if LOOP is not None and not LOOP.is_closed():
        LOOP.run_until_complete(asyncio.sleep(0))
        LOOP.close()
    LOOP = asyncio.new_event_loop()
    asyncio.set_event_loop(LOOP)


def run_workload(iterations):
    for index in range(iterations):
        task = LOOP.create_task(hold_payload(index))
        PENDING_TASKS.append(task)
    LOOP.run_until_complete(asyncio.sleep(0))
    return {
        "pending_tasks": len(PENDING_TASKS),
    }


if __name__ == "__main__":
    setup()
    print(run_workload(1000))
