#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：OverlayFS 基础信息收集、快速定性，检测是否存在 overlay 问题
# 使用：bash 01_baseline_info.sh [mount_point] [container_id]
# 参数：
#   $1  挂载点路径（可选，默认自动检测所有 overlay 挂载点）
#   $2  容器 ID（可选，Docker 容器场景）
# 说明：本脚本收集五类关键信息并推荐分支诊断脚本
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"
OUT_DIR="/tmp/overlayfs_diagnosis_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"

echo "=================================================================="
echo " OverlayFS 基础信息收集"
echo " 生成时间：$(date)"
echo " 目标挂载：${TARGET:-"（自动检测所有 overlay 挂载）"}"
echo " 容器 ID ：${CONTAINER:-"（非 Docker 场景）"}"
echo " 结果目录：${OUT_DIR}"
echo "=================================================================="

echo ""
echo "正在收集各项信息..."
echo "------------------------------------------------------------------"

# ─────────────────────────────────────────────────────────────────────
# 1. 系统基础信息
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "【1/5】系统基础信息"
echo "------------------------------------------------------------------"
echo "内核版本: $(uname -r)"
echo "架构:     $(uname -m)"
echo "发行版:   $(head -1 /etc/os-release 2>/dev/null || cat /etc/issue 2>/dev/null || echo 'unknown')"

if lsmod 2>/dev/null | grep -q overlay; then
  echo "overlay 模块: 已加载"
else
  echo "overlay 模块: 未加载（尝试 modprobe overlay 或内核不支持）"
fi

if modinfo overlay 2>/dev/null | grep -q '^filename'; then
  echo "overlay 模块版本: $(modinfo overlay 2>/dev/null | grep '^version' | head -1 || echo '版本不可用')"
  echo "--- overlay 模块参数 ---"
  for param in /sys/module/overlay/parameters/*; do
    echo "  $(basename ${param}) = $(cat ${param})"
  done 2>/dev/null || echo "  （无法访问模块参数，可能是内置模块）"
fi

# ─────────────────────────────────────────────────────────────────────
# 2. Overlay 挂载拓扑
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "【2/5】Overlay 挂载拓扑"
echo "------------------------------------------------------------------"

if [[ -n "${TARGET}" ]]; then
  echo "目标挂载点: ${TARGET}"
fi

# 收集所有 overlay 挂载
mount | grep -E "^overlay|^overlay2" > "${OUT_DIR}/mount_overlay.txt" 2>/dev/null || true
cat /proc/self/mountinfo | grep -E "overlay" > "${OUT_DIR}/mountinfo_overlay.txt" 2>/dev/null || true

OVERLAY_COUNT=$(wc -l < "${OUT_DIR}/mount_overlay.txt" 2>/dev/null || echo 0)
if [[ "${OVERLAY_COUNT}" -gt 0 ]]; then
  echo "找到 ${OVERLAY_COUNT} 个 overlay 挂载点："
  cat "${OUT_DIR}/mount_overlay.txt"
  echo ""
  echo "详细挂载信息（mountinfo）："
  cat "${OUT_DIR}/mountinfo_overlay.txt"
  echo ""

  # 提取 upperdir/lowerdir/workdir（从 mountinfo）
  while IFS= read -r line; do
    MNT_POINT=$(echo "$line" | awk '{print $5}')
    echo "--- 挂载点: ${MNT_POINT} ---"
    # mountinfo 的第 10 个字段开始是挂载选项（逗号分隔）
    OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' | grep -oP 'lowerdir=[^,]+|upperdir=[^,]+|workdir=[^,]+' | tr '\n' ' ')
    echo "  选项: ${OPTIONS}"

    # 解析各层路径
    LOWER_DIR=$(echo "$OPTIONS" | grep -oP 'lowerdir=\K[^ ]+')
    UPPER_DIR=$(echo "$OPTIONS" | grep -oP 'upperdir=\K[^ ]+')
    WORK_DIR=$(echo "$OPTIONS" | grep -oP 'workdir=\K[^ ]+')

    if [[ -n "${UPPER_DIR}" ]]; then
      echo "  上层文件系统: $(df -hT "${UPPER_DIR}" 2>/dev/null | tail -1 | awk '{print $1, $2, $3}')"
      echo "  上层统计: $(stat -c '%d %F' "${UPPER_DIR}" 2>/dev/null)"
    fi
    if [[ -n "${LOWER_DIR}" ]]; then
      IFS=':' read -ra LOWER_PARTS <<< "${LOWER_DIR}"
      for i in "${!LOWER_PARTS[@]}"; do
        echo "  下层[$i] 文件系统: $(df -hT "${LOWER_PARTS[$i]}" 2>/dev/null | tail -1 | awk '{print $1, $2}')"
      done
    fi
  done < "${OUT_DIR}/mountinfo_overlay.txt"
else
  echo "未找到活跃的 overlay 挂载点。"
fi

# ─────────────────────────────────────────────────────────────────────
# 3. Docker overlay2 状态（容器场景）
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "【3/5】Docker overlay2 状态"
echo "------------------------------------------------------------------"

if command -v docker &>/dev/null; then
  docker info 2>/dev/null | grep -i "storage\|overlay" > "${OUT_DIR}/docker_storage.txt" || true
  echo "Docker 存储驱动信息:"
  cat "${OUT_DIR}/docker_storage.txt" 2>/dev/null || echo "  （无法获取）"

  if [[ -n "${CONTAINER}" ]]; then
    docker inspect "${CONTAINER}" 2>/dev/null | jq '.[0].GraphDriver' > "${OUT_DIR}/docker_container_graphdriver.json" 2>/dev/null || true
    echo ""
    echo "容器 ${CONTAINER} 存储驱动详情:"
    cat "${OUT_DIR}/docker_container_graphdriver.json" 2>/dev/null || echo "  （无法获取容器信息）"
  fi

  # Docker 系统状态
  docker system df 2>/dev/null > "${OUT_DIR}/docker_system_df.txt" || true
  if [[ -s "${OUT_DIR}/docker_system_df.txt" ]]; then
    echo ""
    echo "Docker 磁盘使用:"
    cat "${OUT_DIR}/docker_system_df.txt"
  fi

  # overlay2 目录大小
  if [[ -d /var/lib/docker/overlay2 ]]; then
    echo ""
    echo "overlay2 存储目录:"
    du -sh /var/lib/docker/overlay2/ 2>/dev/null || echo "  （无访问权限）"
    du -sh /var/lib/docker/overlay2/*/diff/ 2>/dev/null | sort -rh | head -10 > "${OUT_DIR}/docker_overlay2_toplayers.txt" || true
    echo "Top 10 容器层:"
    cat "${OUT_DIR}/docker_overlay2_toplayers.txt" 2>/dev/null || echo "  （无法统计）"
  fi
else
  echo "  Docker 未安装或不可用。"
fi

# ─────────────────────────────────────────────────────────────────────
# 4. dmesg 异常关键字
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "【4/5】dmesg OverlayFS 异常日志"
echo "------------------------------------------------------------------"

dmesg 2>/dev/null | grep -i "overlay" > "${OUT_DIR}/dmesg_overlay.txt" || true
if [[ -s "${OUT_DIR}/dmesg_overlay.txt" ]]; then
  cat "${OUT_DIR}/dmesg_overlay.txt"
else
  echo "  未找到 overlay 相关内核日志。"
fi

# ─────────────────────────────────────────────────────────────────────
# 5. 磁盘与 inode 状态
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "【5/5】磁盘与 inode 状态"
echo "------------------------------------------------------------------"

echo "文件系统空间:"
if [[ -d /var/lib/docker ]]; then
  df -hT /var/lib/docker 2>/dev/null || df -hT / 2>/dev/null | head -2
  echo ""
  echo "Inode 使用率:"
  df -i /var/lib/docker 2>/dev/null || df -i / 2>/dev/null | head -2
else
  df -hT 2>/dev/null | head -5
  echo ""
  echo "Inode 使用率（关键分区）:"
  df -i 2>/dev/null | head -5
fi

# ─────────────────────────────────────────────────────────────────────
# 故障分支推荐
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "=================================================================="
echo " 故障分支推荐"
echo "=================================================================="

DMESG_FILE="${OUT_DIR}/dmesg_overlay.txt"
MATCHED=0

if [[ -s "${DMESG_FILE}" ]]; then
  echo ""
  echo "基于 dmesg 关键字的推荐："
  echo "------------------------------------------------------------------"

  while IFS= read -r line; do
    lower_line=$(echo "$line" | tr '[:upper:]' '[:lower:]')

    if echo "$lower_line" | grep -iq "failed to get directory\|not supported as upperdir\|workdir is not\|failed to create workdir\|failed to get kernel config"; then
      echo "  → ${line}"
      echo "    推荐：scripts/branch_A_config_error.sh（配置错误）" | head -1
      MATCHED=1
    fi

    if echo "$lower_line" | grep -iq "filesystem.*not supported\|upper fs not supported"; then
      echo "  → ${line}"
      echo "    推荐：scripts/branch_B_fs_incompatible.sh（下层文件系统不兼容）" | head -1
      MATCHED=1
    fi

    if echo "$lower_line" | grep -iq "not on same filesystem\|cross-device\|xdev\|upperdir.*different"; then
      echo "  → ${line}"
      echo "    推荐：scripts/branch_C_cross_device.sh（跨设备 overlay）" | head -1
      MATCHED=1
    fi

    if echo "$lower_line" | grep -iq "redirect_dir.*disabled\|redirect_dir.*unavailable\|metacopy"; then
      echo "  → ${line}"
      echo "    推荐：scripts/branch_I_redirect_metacopy.sh（redirect_dir/metacopy 冲突）" | head -1
      MATCHED=1
    fi

    if echo "$lower_line" | grep -iq "xino.*disabled\|inode number collision\|stacking depth exceeded"; then
      echo "  → ${line}"
      echo "    推荐：scripts/branch_Z_general.sh（通用诊断）" | head -1
      MATCHED=1
    fi
  done < "${DMESG_FILE}"
fi

echo ""
echo "基于系统状态的推荐："
echo "------------------------------------------------------------------"

# 检查是否有大量 whiteout
WHITEOUT_COUNT=$(find /var/lib/docker/overlay2 -name ".wh.*" 2>/dev/null | wc -l || echo 0)
if [[ "${WHITEOUT_COUNT}" -gt 1000 ]]; then
  echo "  ✓ whiteout 文件数: ${WHITEOUT_COUNT}（大量 whiteout 可能存在文件\"消失\"问题）"
  echo "    推荐：scripts/branch_D_opaque_whiteout.sh（Opaque Whiteout）"
  MATCHED=1
fi

# 检查 inode 使用率
if command -v df &>/dev/null; then
  INODE_PCT=$(df -i /var/lib/docker 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo 0)
  if [[ "${INODE_PCT}" -gt 90 ]]; then
    echo "  ✓ inode 使用率: ${INODE_PCT}%（inode 接近耗尽）"
    echo "    推荐：scripts/branch_G_docker_inode_exhaust.sh（inode 耗尽）"
    MATCHED=1
  fi
fi

# 检查 diff 目录膨胀
if [[ -d /var/lib/docker/overlay2 ]]; then
  OVERLAY_SIZE_BYTES=$(du -sb /var/lib/docker/overlay2/ 2>/dev/null | awk '{print $1}' || echo 0)
  if [[ "${OVERLAY_SIZE_BYTES}" -gt 10737418240 ]]; then  # > 10GB
    echo "  ✓ overlay2 目录大小: $(du -sh /var/lib/docker/overlay2/ 2>/dev/null | awk '{print $1}')（较大）"
    echo "    推荐：scripts/branch_H_docker_diff_bloat.sh（diff 目录膨胀）"
    MATCHED=1
  fi
fi

# 检查 copy-up 相关（strace 方式）
if [[ ${MATCHED} -eq 0 ]]; then
  echo "  - 未匹配到特定分支，建议执行通用诊断"
  echo "    推荐：scripts/branch_Z_general.sh（通用诊断）"
fi

echo ""
echo "=================================================================="
echo " 信息收集完成，结果目录：${OUT_DIR}"
echo " 根据以上推荐执行对应的分支诊断脚本。"
echo "=================================================================="
