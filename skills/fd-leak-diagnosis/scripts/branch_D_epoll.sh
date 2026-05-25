#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_epoll.sh
# 用途：epoll FD 泄漏诊断 — L3 类型层 + L4 根因层
# 使用：bash branch_D_epoll.sh <target_pid>
# 参数：
#   $1  目标 PID
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：epoll FD 泄漏诊断"
  echo "使用：bash $0 <target_pid>"
  echo "  target_pid: 目标进程 PID"
  exit 0
fi

if [[ ! -d "/proc/${TARGET_PID}" ]]; then
  echo "[错误] PID ${TARGET_PID} 不存在"
  exit 1
fi

echo "=================================================================="
echo " 分支D：epoll FD 泄漏 —— L3 类型层 + L4 根因层"
echo " 目标 PID: ${TARGET_PID}"
echo "=================================================================="

# D1. epoll 实例统计
echo ""
echo "【D1】epoll 实例统计"
echo "------------------------------------------------------------------"
epoll_count=$(ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep -c "eventpoll" || echo 0)
echo "  eventpoll FD 数量: ${epoll_count}"
if [[ $epoll_count -gt 2 ]]; then
  echo "  状态: ⚠ epoll 实例数 > 2，可能存在泄漏！"
elif [[ $epoll_count -eq 0 ]]; then
  echo "  状态: 无 epoll FD（可能不是事件驱动程序）"
else
  echo "  状态: 正常（1-2 个 epoll 实例）"
fi

# D2. epoll FD 详情
echo ""
echo "【D2】epoll FD 详情"
echo "------------------------------------------------------------------"
ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep "eventpoll" | head -20

# D3. 进程 FD 中 epoll 占比
echo ""
echo "【D3】epoll 占全部 FD 比例"
echo "------------------------------------------------------------------"
total_fds=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
epoll_pct=$(awk "BEGIN {printf \"%.1f\", ${epoll_count} / ${total_fds} * 100}" 2>/dev/null || echo "N/A")
echo "  总 FD: ${total_fds} | epoll FD: ${epoll_count} (${epoll_pct}%)"

# D4. strace epoll 系统调用追踪
echo ""
echo "【D4】epoll 系统调用追踪（L4 根因层）"
echo "------------------------------------------------------------------"
if command -v strace &>/dev/null; then
  echo "  执行（30 秒采样）：strace -p ${TARGET_PID} -e trace=epoll_create,epoll_create1,close -c"
  echo "  注意：strace 会显著降低进程性能！"
  echo ""
  echo "  建议执行的命令："
  echo "    timeout 30 strace -p ${TARGET_PID} -e trace=epoll_create,epoll_create1,close -c 2>&1"
  echo ""
  echo "  正常情况：epoll_create1 调用数 ≈ close(epfd) 调用数"
  echo "  泄漏情况：epoll_create1 >> close(epfd)"
else
  echo "  strace 不可用，跳过系统调用追踪"
fi

# D5. epoll 泄漏排查指引
echo ""
echo "【D5】epoll 泄漏排查指引"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  epoll 泄漏常见原因：
    1. epoll_create1() 后未保存 epfd 就丢弃引用
    2. 事件循环出错后未正确 clean up
    3. 子进程 fork 后继承了 epoll FD（缺少 O_CLOEXEC）
    4. epoll_ctl(EPOLL_CTL_DEL) 未在 fd close() 前调用

  排查方法：
    - strace 对比 epoll_create1 和 close 的调用次数
    - 检查代码中每个 epoll_create1 是否有对应的 close
    - 使用 valgrind --track-fds=yes 检测泄漏点
GUIDE

echo ""
echo "=================================================================="
echo " 分支D 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  目标 PID：<PID>
  epoll FD 数：<N>
  总 FD 数：<total>（epoll 占比 <P>%）
  strace 结果：epoll_create1 <N> / close <M>（差 <N-M>）
  判定：[正常/可疑/泄漏]
  建议：<检查 epoll 实例创建和销毁是否成对出现>
CONCLUSION
