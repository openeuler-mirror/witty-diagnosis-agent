#!/bin/bash
# entrypoint.sh — Memory leak diagnosis test entrypoint
set -e
echo "================================================"
echo "  Memory Leak Diagnosis — Test Entry"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"
echo ""
echo "=== Creating test memory scenarios ==="
# Create a background process that slowly allocates memory
cat > /tmp/memleak_test.py << 'PYEOF'
import time
import os

# Simulate memory leak: grow list by 1000 elements every second
leak = []
i = 0
print(f"Memleak test PID: {os.getpid()}")
while True:
    leak.extend([0] * 100000)  # ~800KB per iteration
    i += 1
    if i % 10 == 0:
        rss = int(open(f"/proc/{os.getpid()}/status").read().split("VmRSS:")[1].split()[0])
        print(f"Iteration {i}: RSS={rss} kB")
    time.sleep(1)
PYEOF

echo "=== Starting memory leak simulator ==="
python3 /tmp/memleak_test.py &
LEAK_PID=$!
echo "Leak simulator PID: $LEAK_PID"

echo ""
echo "=== Running baseline collection ==="
bash /skills/memory-leak-diagnosis/collect_mem_info.sh -p $LEAK_PID -i 3 -c 3 2>&1 || true

echo ""
echo "=== Tests done, keeping container alive ==="
echo "Leak simulator running at PID $LEAK_PID"
echo "Run diagnosis commands manually or wait for automated tests"
sleep 3600
