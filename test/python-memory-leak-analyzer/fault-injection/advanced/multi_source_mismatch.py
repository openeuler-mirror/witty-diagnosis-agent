"""Small obvious global leak plus larger hidden listener/cache leak."""

from functools import lru_cache


SMALL_GLOBAL = []
LISTENERS = []


class LargeTenant:
    def __init__(self, tenant_id):
        self.tenant_id = tenant_id
        self.payload = "large-tenant-state" * 1024

    def callback(self):
        return self.tenant_id


@lru_cache(maxsize=None)
def tenant_lookup(tenant_id):
    return {
        "tenant_id": tenant_id,
        "profile": "tenant-cache-profile" * 1024,
    }


def setup():
    SMALL_GLOBAL.clear()
    LISTENERS.clear()
    tenant_lookup.cache_clear()


def run_workload(iterations):
    for index in range(iterations):
        if index % 20 == 0:
            SMALL_GLOBAL.append({"index": index})
        tenant = LargeTenant(index)
        LISTENERS.append(tenant.callback)
        tenant_lookup(index)
    return {
        "small_global_len": len(SMALL_GLOBAL),
        "listener_count": len(LISTENERS),
        "cache_info": tenant_lookup.cache_info()._asdict(),
    }


if __name__ == "__main__":
    print(run_workload(2000))
