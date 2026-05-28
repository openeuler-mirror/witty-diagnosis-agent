#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_inotify.sh
# 用途：OverlayFS inotify 失效诊断 —— inotify 在 merged 目录无事件
# 场景：inotifywait -m /merged 没有事件；使用 inotify 的应用行为异常
# 使用：bash branch_F_inotify.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"

echo "=================================================================="
echo " 分支F：OverlayFS inotify 失效诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# F1. 确认内核版本与 inotify 状态
# --------------------------------------------------------------------------
echo ""
echo "【F1】内核版本与 inotify 支持"
echo "------------------------------------------------------------------"

KERNEL=$(uname -r | cut -d'-' -f1)
echo "内核版本: $(uname -r)"
echo "主版本: ${KERNEL}"

# 对比已知修复版本
echo ""
echo "已知 inotify + overlay 兼容性："
echo "  v3.18—v5.11: overlay 上 inotify 有已知问题"
echo "    （v5.12 commit 3e2b0e33 修复）"
echo "  v5.12+: inotify + overlay 基本正常"
echo ""

if [[ "$(echo "${KERNEL}" | cut -d'.' -f1)" -lt 5 ]] ||
   { [[ "$(echo "${KERNEL}" | cut -d'.' -f1)" -eq 5 ]] && [[ "$(echo "${KERNEL}" | cut -d'.' -f2)" -lt 12 ]]; }; then
  echo "⚠️ 当前内核版本低于 v5.12，存在已知的 overlay inotify 不完整问题"
fi

echo ""
echo "当前 inotify 限制："
echo "  max_user_watches:   $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 'N/A')"
echo "  max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 'N/A')"
echo "  max_queued_events:  $(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null || echo 'N/A')"

# --------------------------------------------------------------------------
# F2. inotify 功能验证
# --------------------------------------------------------------------------
echo ""
echo "【F2】inotify 功能测试（merged 层）"
echo "------------------------------------------------------------------"

if [[ -z "${TARGET}" || ! -d "${TARGET}" ]]; then
  echo "挂载点不可用，自动检测..."
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
  if [[ -z "${TARGET}" ]]; then
    echo "没有活跃的 overlay 挂载点"
    exit 1
  fi
fi

echo "测试挂载点: ${TARGET}"

if ! command -v inotifywait &>/dev/null; then
  echo "inotifywait 未安装，需要安装 inotify-tools"
  echo "跳过自动测试，使用以下手动验证步骤："
  echo ""
fi

# 功能测试
TEST_DIR="${TARGET}/.inotify_test_$(date +%s)"
mkdir -p "${TEST_DIR}"

echo ""
echo "测试1：inotify 事件接收（请观察 3 秒内的事件）"
echo "------------------------------------------------------------------"

# 启动后台 inotifywait
if command -v inotifywait &>/dev/null; then
  inotifywait -t 3 -e create,delete,modify,move "${TEST_DIR}" 2>/dev/null &
  INOTIFY_PID=$!
  sleep 0.5

  # 触发事件
  echo "test" > "${TEST_DIR}/testfile"
  mv "${TEST_DIR}/testfile" "${TEST_DIR}/testfile2"
  rm "${TEST_DIR}/testfile2"

  wait ${INOTIFY_PID} 2>/dev/null || true
  INOTIFY_EXIT=$?

  if [[ ${INOTIFY_EXIT} -eq 0 ]]; then
    echo ""
    echo "  ✓ merged 层 inotify 事件正常接收"
  else
    echo ""
    echo "  ✗ merged 层 inotify 没有收到事件（exit code: ${INOTIFY_EXIT}）"
    echo "  可能原因：overlay inotify 事件未被正确传递"
  fi
else
  echo "  inotifywait 不可用，请手动测试："
  echo "  terminal 1: inotifywait -m ${TARGET}"
  echo "  terminal 2: touch ${TARGET}/testfile"
fi

rm -rf "${TEST_DIR}" 2>/dev/null || true

# --------------------------------------------------------------------------
# F3. 内核态分析指引
# --------------------------------------------------------------------------
echo ""
echo "【F3】内核态分析指引"
echo "------------------------------------------------------------------"
cat << 'KERNEL_GUIDE'

inotify 在 OverlayFS 上的内核行为：

问题根因（< v5.12）：
  overlay 的 dentry 操作不会为 merged 视图传播 inotify 事件。
  在 v3.18—v5.11 期间，overlayfs 的 readdir/file 操作绕过了
  VFS 层的 inotify 回调（因为 overlay 使用自己的 inode 操作集）。

  v5.12 修复（commit 3e2b0e33）：
    "ovl: fix missing inotify event on copy-up"
  修复了 copy-up 操作后 inotify 事件丢失的问题。

  但仍有部分事件存在限制（截至 v6.x）：
  - lower → upper 的访问路径变化（如文件从 lower 首次被打开）
    可能不会产生 inotify 事件
  - 某些元数据操作（如 utimens）可能不触发事件

检查方法：
  # 确认 overlay inotify 相关的内核配置
  grep CONFIG_INOTIFY_USER /boot/config-$(uname -r) 2>/dev/null || echo "  N/A"

  # 使用 tracepoint 监控 VFS inotify 事件
  echo 1 > /sys/kernel/debug/tracing/events/fs/inotify/enable
  cat /sys/kernel/debug/tracing/trace_pipe

内核代码路径：
  fs/notify/inotify/inotify_fsnotify.c — inotify 事件生成
  fs/overlayfs/file.c — overlay 文件操作（事件源头）
  fs/overlayfs/inode.c — overlay inode 操作

KERNEL_GUIDE

# --------------------------------------------------------------------------
# F4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【F4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

根据诊断结果选择：

方案1（推荐）：升级内核到 v5.12+
  - 修复了 most overlay inotify 事件传递问题。
  - 最小风险，收益最大。

方案2（变通）：在 upperdir 上直接监听
  - 不在 merged 上监听，而是在 upperdir 上监听
  - upperdir 是普通文件系统，inotify 正常工作
  - 需要注意 upperdir 中的文件变化不完全等于 merged 中的变化

方案3（应用层 workaround）：使用轮询替代
  - 使用 polling（如 watchman、定期 stat）替代 inotify
  - 性能开销较大，但不受 overlay 限制
  - 适用场景：监控频率不高的目录

方案4（容器场景）：使用 volume 或 bind mount
  - 对于需要 inotify 的目录，使用 volume 或 bind mount
  - 绕过 overlay，直接使用主机的文件系统
  - 示例：docker run -v /host/path:/container/path ...

方案5（Docker Compose 场景）：
  volumes:
    - ./src:/app/src          # 需要 inotify 的目录使用 bind mount
    # 而不是依赖容器内的 overlay 层
FIX_SUGGESTIONS
