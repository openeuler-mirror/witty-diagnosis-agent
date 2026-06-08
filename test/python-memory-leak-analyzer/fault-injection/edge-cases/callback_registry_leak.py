"""Global callback registry retains bound methods and service instances."""


LISTENER_REGISTRY = []


class ServiceClient:
    def __init__(self, client_id):
        self.client_id = client_id
        self.payload = {"client_id": client_id, "buffer": "listener" * 512}

    def on_event(self, event):
        return self.payload["client_id"], event


def setup():
    LISTENER_REGISTRY.clear()


def run_workload(iterations):
    for index in range(iterations):
        client = ServiceClient(index)
        LISTENER_REGISTRY.append(client.on_event)
    return {
        "listener_count": len(LISTENER_REGISTRY),
    }


if __name__ == "__main__":
    print(run_workload(2000))
