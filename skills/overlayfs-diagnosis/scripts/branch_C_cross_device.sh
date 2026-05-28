#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_cross_device.sh
# 用途：跨设备 overlay 诊断 —— upperdir/workdir 不在同一设备
# 场景：dmesg 含 "not on same filesystem as workdir" / "cross-device link"
# 使用：bash branch_C_cross_device.sh [mount_point] [container_id]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"

echo "=================================================================="
echo " 分支C：跨设备 Overlay 诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# C1. 检查 upperdir 和 workdir 的设备一致性
# --------------------------------------------------------------------------
echo ""
echo "【C1】设备一致性检查"
echo "------------------------------------------------------------------"

while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")

  UPPER=$(echo "$OPTIONS" | grep -oP 'upperdir=\K[^, ]+' 2>/dev/null || true)
  WORK=$(echo "$OPTIONS" | grep -oP 'workdir=\K[^, ]+' 2>/dev/null || true)
  MNT=$(echo "$line" | awk '{print $3}' 2>/dev/null || echo "${TARGET}")

  echo "挂载点: ${MNT}"

  if [[ -n "${UPPER}" && -n "${WORK}" ]]; then
    echo "  upperdir: ${UPPER}"
    echo "  workdir:  ${WORK}"

    if [[ -e "${UPPER}" && -e "${WORK}" ]]; then
      echo ""
      echo "  设备号对比:"
      echo "    upperdir: $(stat -c 'dev=%d  mount_id=%m' "${UPPER}" 2>/dev/null || echo 'stat 失败')"
      echo "    workdir:  $(stat -c 'dev=%d  mount_id=%m' "${WORK}" 2>/dev/null || echo 'stat 失败')"

      echo ""
      echo "  文件系统对比:"
      echo "    upperdir: $(df -hT "${UPPER}" 2>/dev/null | tail -1)"
      echo "    workdir:  $(df -hT "${WORK}" 2>/dev/null | tail -1)"
    else
      echo "  ✗ upperdir 或 workdir 路径不存在！"
    fi
  else
    echo "  无法从挂载信息中提取 upperdir/workdir"
  fi
  echo "---"
  echo ""
done < <(mount | grep -E "^overlay" 2>/dev/null || echo "${TARGET}")

# --------------------------------------------------------------------------
# C2. 所有 lowerdir 的设备信息（多层场景）
# --------------------------------------------------------------------------
echo ""
echo "【C2】所有 lowerdir 设备信息"
echo "------------------------------------------------------------------"

while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")
  LOWER=$(echo "$OPTIONS" | grep -oP 'lowerdir=\K[^, ]+' 2>/dev/null || true)

  if [[ -n "${LOWER}" ]]; then
    IFS=':' read -ra LOWER_PARTS <<< "${LOWER}"
    echo "lowerdir 共 ${#LOWER_PARTS[@]} 层："
    for i in "${!LOWER_PARTS[@]}"; do
      LP="${LOWER_PARTS[$i]}"
      if [[ -e "${LP}" ]]; then
        echo "  [${i}] ${LP} → 设备:$(stat -c '%d' "${LP}") FS:$(df -hT "${LP}" 2>/dev/null | tail -1 | awk '{print $2}')"
      else
        echo "  [${i}] ${LP} → [路径不存在]"
      fi
    done
  fi
done < <(mount | grep -E "^overlay" 2>/dev/null || echo "${TARGET}")

# --------------------------------------------------------------------------
# C3. 内核约束说明
# --------------------------------------------------------------------------
echo ""
echo "【C3】内核约束说明"
echo "------------------------------------------------------------------"
cat << 'KERNEL_CONSTRAINT'

OverlayFS 内核要求：
  upperdir 和 workdir 必须在同一文件系统（同一 super_block）。
  这是内核强制约束（ovl_mount_dir_noesc() → ovl_same_fs()）。
  原因：workdir 用于存放 copy-up 时的临时文件，需要和 upperdir 在同一设备
  以保证原子重命名操作（rename() 在同一设备是原子的，跨设备则不是）。

  lowerdir 可以跨设备——每层可以在不同的文件系统上。

  Docker overlay2 场景：
  /var/lib/docker 通常在一个分区上，因此 Docker 自动管理的 upper/work 默认在同一设备。
  如果你通过 --mount type=bind 映射了外部目录到容器中，这些目录在容器的不同设备上，
  但不会影响 overlay 本身——overlay 的 upper/work 仍然是 /var/lib/docker 分区。

KERNEL_CONSTRAINT

# --------------------------------------------------------------------------
# C4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【C4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

修复方案：

方案1（推荐）：将 upperdir 和 workdir 放在同一文件系统
  # 假设 /data1 是 ext4，/data2 也是 ext4（不同分区），需要统一
  mkdir -p /data1/upper /data1/work
  mount -t overlay overlay \
    -o lowerdir=/lower,upperdir=/data1/upper,workdir=/data1/work \
    /merged

方案2（使用 bind mount 变通）：如果必须跨设备
  # 在 workdir 所在设备上创建 upperdir 指向
  mkdir -p /work_device/upper /work_device/work
  # 然后将文件从原 upperdir 同步过来
  rsync -a /original_upper/ /work_device/upper/
  # 最后使用新路径挂载
  mount -t overlay overlay \
    -o lowerdir=/lower,upperdir=/work_device/upper,workdir=/work_device/work \
    /merged

方案3（Docker 场景）：
  # 检查 /var/lib/docker 是否跨设备和分区
  # 如果是，迁移整个 /var/lib/docker 到单一分区
  systemctl stop docker
  rsync -a /var/lib/docker/ /new/location/docker/
  # 修改 /etc/docker/daemon.json 添加 "data-root": "/new/location/docker"
  systemctl start docker
FIX_SUGGESTIONS
