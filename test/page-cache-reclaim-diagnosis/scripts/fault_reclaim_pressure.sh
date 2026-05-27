#!/bin/bash
# fault_reclaim_pressure.sh -- inject memory reclaim pressure
# Simulates kswapd/direct reclaim by rapidly allocating + freeing memory
set -euo pipefail

echo "[FAULT] PID=$$  Reclaim pressure injector"
DURATION=${1:-120}  # run for N seconds (default 120)
ALLOC_SIZE=${2:-500}  # allocate N MB each round (default 500)

echo "[FAULT] Creating reclaim pressure for ${DURATION}s, ${ALLOC_SIZE}MB/round..."
END=$((SECONDS + DURATION))
ROUND=0

while [ $SECONDS -lt $END ]; do
    ROUND=$((ROUND + 1))
    
    # Allocate memory rapidly
    python3 -c "
import mmap, os, time
addrs = []
target = ${ALLOC_SIZE}
# Allocate in 1MB chunks
for i in range(target):
    try:
        m = mmap.mmap(-1, 1024 * 1024, prot=mmap.PROT_READ|mmap.PROT_WRITE)
        # Touch each page to force physical allocation
        m[0] = 0
        addrs.append(m)
    except OSError:
        print(f'[FAULT] Allocation failed at {i}MB', flush=True)
        break
if len(addrs) >= target:
    print(f'[FAULT] Round $ROUND: allocated {target}MB, holding for 2s', flush=True)
else:
    print(f'[FAULT] Round $ROUND: allocated {len(addrs)}MB only, holding', flush=True)

time.sleep(2)

# Release memory
for m in addrs:
    m.close()
print(f'[FAULT] Round $ROUND: released memory', flush=True)

# Brief pause to let kswapd catch up
time.sleep(1)
"

    # Report vmstat
    echo "[FAULT] Round $ROUND vmstat: allocstall=$(grep ^allocstall /proc/vmstat | awk '{print $2}')  pgscan_direct=$(grep ^pgscan_direct /proc/vmstat | awk '{print $2}')"
done

echo "[FAULT] Reclaim pressure injection done"
