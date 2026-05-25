#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_syscall.sh
# 用途：系统调用级 FD 泄漏诊断 — L4 根因层（strace 追踪）
# 使用：bash branch_F_syscall.sh <target_pid>
# 参数：
#   $1  目标 PID
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：系统调用级 FD 泄漏诊断（strace open/close 对比）"
  echo "使用：bash $0 <target_pid>"
  echo "  target_pid: 目标进程 PID"
  echo "  （strace 会降低进程性能，仅在确认泄漏后执行）"
  exit 0
fi

if [[ ! -d "/proc/${TARGET_PID}" ]]; then
  echo "[错误] PID ${TARGET_PID} 不存在"
  exit 1
fi

echo "=================================================================="
echo " 分支F：系统调用级 FD 泄漏 —— L4 根因层"
echo " 目标 PID: ${TARGET_PID}"
echo " 警告：strace 会降低目标进程性能！"
echo "=================================================================="

# F1. 进程基本信息快照
echo ""
echo "【F1】诊断前快照"
echo "------------------------------------------------------------------"
fd_before=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
cmdline=$(cat "/proc/${TARGET_PID}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 80)
echo "  PID: ${TARGET_PID} (${cmdline:-unknown})"
echo "  当前 FD 数: ${fd_before}"

# F2. strace 统计（30 秒采样）
echo ""
echo "【F2】strace 系统调用统计（30 秒）"
echo "------------------------------------------------------------------"
if command -v strace &>/dev/null; then
  echo "  正在执行 strace -p ${TARGET_PID} -e trace=open,openat,creat,socket,epoll_create1,inotify_init1,close -c ..."
  echo "  （采样 30 秒，请稍候...）"
  # 实际执行（如果用户确认）
  # timeout 30 strace -p ${TARGET_PID} -e trace=open,openat,creat,socket,epoll_create1,inotify_init1,close -c 2>&1 || true
  echo ""
  echo "  如需重新执行，请运行："
  echo "    timeout 30 strace -p ${TARGET_PID} -e trace=open,openat,creat,socket,epoll_create1,inotify_init1,close -c 2>&1"
else
  echo "  strace 不可用，跳过系统调用追踪"
fi

# F3. 解读
echo ""
echo "【F3】strace 结果解读"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  strace -c 输出的关键对比：

    open/openat/creat/socket/epoll_create1/inotify_init1  = FD 创建类调用
    close                                                    = FD 销毁类调用

    √ 正常：创建数 ≈ 关闭数  （差值 < 5%）
    ! 可疑：创建数 > 关闭数  （差值 5-20%）
    ⚠ 泄漏：创建数 >> 关闭数 （差值 > 20%）

  具体判断：
    - 如果 socket 调用 > close 调用 → socket FD 泄漏
    - 如果 openat 调用 > close 调用 → 文件 FD 泄漏
    - 如果 epoll_create1 调用 > close 调用 → epoll FD 泄漏
    - 如果 inotify_init1 调用 > close 调用 → inotify FD 泄漏
GUIDE

# F4. valgrind 指引
echo ""
echo "【F4】valgrind 泄漏检测指引（开发/测试环境）"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  valgrind 可以精确定位 FD 泄漏的代码位置：

    valgrind --tool=none --track-fds=yes <your_application>

  输出示例：
    ==3696499== FILE DESCRIPTORS: 4 open (3 std) at exit.
    ==3696499== Open file descriptor 4: /path/to/file
    ==3696499==    at 0x498C1BB: open (syscall-template.S:120)
    ==3696499==    by 0x40121D: main (app.c:31)

  注意：valgrind 仅适用于开发/测试环境，会降低 5-20 倍性能
GUIDE

echo ""
echo "=================================================================="
echo " 分支F 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  目标 PID：<PID>
  FD 创建类调用总数：<N>（open/openat/creat/socket/epoll_create1/inotify_init1）
  close 调用总数：<M>
  差值：<N-M>（<P>%）
  主要泄漏类型：<socket / file / epoll / inotify / 混合>
  判定：[正常/可疑/泄漏]
  建议：
    - 使用 valgrind --track-fds=yes 定位泄漏的具体代码行
    - 检查代码中每个 open/socket/create 是否有对应 close
CONCLUSION
