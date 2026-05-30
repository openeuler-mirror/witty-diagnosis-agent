#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_copyup_perf.sh
# 用途：Copy-up 性能退化诊断 —— 首次写入 overlay 文件时延迟高
# 场景：文件读取/写入变慢，ioprofile 显示 copy-up 耗时；容器首次写入日志/数据慢
# 使用：bash branch_E_copyup_perf.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"

echo "=================================================================="
echo " 分支E：Copy-up 性能退化诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# E1. 确认文件状态：在 merged 中文件来自 lower 还是 upper
# --------------------------------------------------------------------------
echo ""
echo "【E1】确认文件状态（lower vs upper）"
echo "------------------------------------------------------------------"

if [[ -z "${TARGET}" || ! -d "${TARGET}" ]]; then
  echo "挂载点不可用，尝试自动检测..."
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
  if [[ -z "${TARGET}" ]]; then
    echo "没有活跃的 overlay 挂载点。"
    exit 1
  fi
fi

echo "挂载点: ${TARGET}"

# 找一些大文件
echo ""
echo "大文件扫描（可能触发耗时 copy-up）："
find "${TARGET}" -type f -size +10M 2>/dev/null | head -10

# 检查文件设备的来源
echo ""
echo "文件设备号分析（设备号与 upper/lower 一致表示尚未 copy-up）："
for f in $(find "${TARGET}" -type f -size +1M 2>/dev/null | head -5); do
  F_DEV=$(stat -c "%d" "${f}" 2>/dev/null)
  echo "  ${f} (${F_DEV})"
done

# 获取 upper 设备的 device number
OPTIONS=$(mount | grep overlay | grep "${TARGET}" | grep -oP 'upperdir=[^, ]+' | head -1 | cut -d'=' -f2)
if [[ -n "${OPTIONS}" ]]; then
  UPPER_DEV=$(stat -c "%d" "${OPTIONS}" 2>/dev/null)
  echo ""
  echo "upperdir 设备号: ${UPPER_DEV}（来自 ${OPTIONS}）"
  echo "文件若属于此设备，说明已经 copy-up 到 upper："
  for f in $(find "${TARGET}" -type f -size +1M 2>/dev/null | head -5); do
    F_DEV=$(stat -c "%d" "${f}" 2>/dev/null)
    if [[ "${F_DEV}" == "${UPPER_DEV}" ]]; then
      echo "  ✓ ${f} → 已 copy-up（up-to-date）"
    else
      echo "  ⚠️ ${f} → 尚在 lower（写入将触发 copy-up）"
    fi
  done
fi

# --------------------------------------------------------------------------
# E2. 文件分布统计
# --------------------------------------------------------------------------
echo ""
echo "【E2】merged 目录文件统计"
echo "------------------------------------------------------------------"

echo "merged 中文件总数: $(find "${TARGET}" -type f 2>/dev/null | wc -l)"
echo "merged 中目录总数: $(find "${TARGET}" -type d 2>/dev/null | wc -l)"
echo "merged 中大文件(>100M): $(find "${TARGET}" -type f -size +100M 2>/dev/null | wc -l)"
echo "merged 中小文件(<1K): $(find "${TARGET}" -type f -size -1K 2>/dev/null | wc -l)"

# Docker 场景
if [[ -n "${CONTAINER}" ]]; then
  echo ""
  echo "容器 ${CONTAINER} 的 diff 层文件统计："
  CONTAINER_HASH=$(docker inspect "${CONTAINER}" 2>/dev/null | jq -r '.[0].GraphDriver.Data.UpperDir' 2>/dev/null || true)
  if [[ -n "${CONTAINER_HASH}" ]]; then
    echo "  diff 目录中文件数: $(find "${CONTAINER_HASH}" -type f 2>/dev/null | wc -l)"
    echo "  diff 目录中目录数: $(find "${CONTAINER_HASH}" -type d 2>/dev/null | wc -l)"
    echo "  diff 目录大小: $(du -sh "${CONTAINER_HASH}" 2>/dev/null | awk '{print $1}')"
  fi
fi

# --------------------------------------------------------------------------
# E3. Copy-up 性能评估
# --------------------------------------------------------------------------
echo ""
echo "【E3】Copy-up 性能评估"
echo "------------------------------------------------------------------"

LARGE_FILE=$(find "${TARGET}" -type f -size +10M 2>/dev/null | head -1)
if [[ -n "${LARGE_FILE}" ]]; then
  echo "复制大文件来模拟 copy-up 操作..."
  echo "  文件: ${LARGE_FILE}"
  echo "  大小: $(stat -c '%s' "${LARGE_FILE}" | numfmt --to=iec 2>/dev/null || stat -c '%s' "${LARGE_FILE}")"
  echo ""

  # 通过写入触发 copy-up
  echo "  执行: dd if=${LARGE_FILE} of=${TARGET}/.copyup_test bs=1M count=10 oflag=direct 2>/dev/null"
  TIMEFORMAT="  Copy-up 耗时（10MB）: %3R 秒"
  time dd if="${LARGE_FILE}" of="${TARGET}/.copyup_test" bs=1M count=10 oflag=direct 2>/dev/null || echo "  （测试失败）"
  rm -f "${TARGET}/.copyup_test" 2>/dev/null || true
  echo ""
  echo "  ⚠️ 如果是首次写入大文件，上述时间实际上包含了一次完整的 copy-up"
  echo "     （从 lower 读取全部数据 → 写入 upper）加上实际写入数据的时间。"
else
  echo "  merged 中没有 >= 10MB 的文件，跳过性能测试。"
  echo "  可以手动执行以下命令模拟 copy-up："
  echo "    dd if=/dev/urandom of=${TARGET}/test_large bs=1M count=100"
  echo "    将触发一次完整 copy-up（100MB 数据从不存在的 lower 文件新建）"
fi

# --------------------------------------------------------------------------
# E4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【E4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

Copy-up 性能退化优化策略：

方案1：启用 metacopy（仅复制元数据，不复制数据）
# 内核 v5.10+ 支持，但需内核编译时启用 CONFIG_OVERLAY_FS_METACOPY=y
# 部分环境（如 WSL2）默认未启用此选项，需要确认后再操作
cat /sys/module/overlay/parameters/metacopy
# 如果 =0，尝试模块参数启用
echo Y > /sys/module/overlay/parameters/metacopy 2>/dev/null || true
# 挂载时指定（需内核支持）：
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work,metacopy=on /merged
# ⚠️ 若内核未编译 CONFIG_OVERLAY_FS_METACOPY，上述操作无效
#    可通过 zcat /proc/config.gz 2>/dev/null | grep OVERLAY_FS_METACOPY 确认

方案2：减少 copy-up 触发频率
  避免对 large lower 文件做 in-place 修改
  考虑在容器初始化时预先 cp 到 upper：
    cp /lower/largefile /merged/largefile
    # 这样在容器运行期间的写入不会再触发 copy-up

方案3：优化文件分布
  对大量小文件的情况（包管理器安装、git clone）：
  - 这些操作会造成大量 copy-up，无法避免
  - 优化方向：使用更快的存储设备，或调整 lower/upper 所在文件系统

方案4：Docker 容器优化
  - 将频繁写入的数据（日志、数据库）挂载为 volume 或 bind mount
  - 使用 tmpfs 挂载 /tmp 等临时目录（避免 overlay 写入）
  - 写密集型应用考虑使用 volume driver（如 local driver with nfs）

方案5：监控 copy-up 事件
  # 使用 tracepoint 监控 copy-up 频率和大小
  echo 1 > /sys/kernel/debug/tracing/events/overlayfs/overlayfs_copy_up/enable
  cat /sys/kernel/debug/tracing/trace_pipe
  # Ctrl+C 停止
  echo 0 > /sys/kernel/debug/tracing/events/overlayfs/overlayfs_copy_up/enable
FIX_SUGGESTIONS
