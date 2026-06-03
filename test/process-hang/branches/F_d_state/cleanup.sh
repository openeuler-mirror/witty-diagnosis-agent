#!/bin/bash
set -euo pipefail
for name in nfs-server-dstate process-hang-branch-f; do
    docker ps -q --filter "name=$name" 2>/dev/null | xargs -r docker kill 2>/dev/null || true
done
echo "[CLEANUP] 完成"
