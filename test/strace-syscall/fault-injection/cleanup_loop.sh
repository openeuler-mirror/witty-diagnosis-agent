#!/usr/bin/env bash
# ================================================================
# cleanup_loop.sh - 清理持续运行的故障容器
# 用法: ./cleanup_loop.sh <branch> [mode]
#       ./cleanup_loop.sh all
# ================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() { echo "Usage: $0 <branch|all> [mode]"; echo "  e.g.: $0 a eacces"; echo "  e.g.: $0 all"; exit 1; }

cleanup_all() {
    print_header "清理全部loop容器"
    containers=$(docker ps -a --filter "name=strace-fi-loop-" --format "{{.ID}} {{.Names}}" 2>/dev/null || true)
    if [ -z "$containers" ]; then print_info "无loop容器"; return; fi
    echo "$containers" | while read -r cid cname; do
        docker kill "${cid}" 2>/dev/null || true
        docker rm "${cid}" 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} ${cname}"
    done
    print_info "清理完成"
}

if [ $# -lt 1 ]; then usage; fi
if [ "$1" = "all" ]; then cleanup_all; exit 0; fi

BRANCH="$1"; MODE="${2:-}"
PATTERN="strace-fi-loop-${BRANCH}"
[ -n "$MODE" ] && PATTERN="strace-fi-loop-${BRANCH}-${MODE}"

containers=$(docker ps -a --filter "name=${PATTERN}" --format "{{.ID}} {{.Names}}" 2>/dev/null || true)
if [ -z "$containers" ]; then print_info "无匹配容器 ($PATTERN)"; exit 0; fi

echo "$containers" | while read -r cid cname; do
    docker kill "${cid}" 2>/dev/null || true
    docker rm "${cid}" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} ${cname}"
done
print_info "清理完成"
