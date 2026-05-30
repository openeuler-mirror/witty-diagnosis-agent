#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_fs_incompatible.sh
# 用途：下层文件系统不兼容诊断 —— overlay 不支持的文件系统
# 场景：dmesg 含 "filesystem on ... not supported" / "upper fs not supported"
# 使用：bash branch_B_fs_incompatible.sh [mount_point] [container_id]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"
CONTAINER="${2:-}"

echo "=================================================================="
echo " 分支B：下层文件系统不兼容诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# B1. 识别各层文件系统类型
# --------------------------------------------------------------------------
echo ""
echo "【B1】各层文件系统类型"
echo "------------------------------------------------------------------"

while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")
  MNT_POINT=$(echo "$line" | awk '{print $3}')
  echo "挂载点: ${MNT_POINT}"

  for dir_param in "upperdir" "lowerdir" "workdir"; do
    DIR_VAL=$(echo "$OPTIONS" | grep -oP "${dir_param}=\K[^, ]+" 2>/dev/null || true)
    if [[ -n "${DIR_VAL}" ]]; then
      FIRST_DIR=$(echo "${DIR_VAL}" | cut -d':' -f1)
      if [[ -e "${FIRST_DIR}" ]]; then
        FS_TYPE=$(df -hT "${FIRST_DIR}" 2>/dev/null | tail -1 | awk '{print $2}')
        FS_DEV=$(df -hT "${FIRST_DIR}" 2>/dev/null | tail -1 | awk '{print $1}')
        echo "  ${dir_param}: ${FIRST_DIR} → ${FS_TYPE} (${FS_DEV})"
      else
        echo "  ${dir_param}: ${FIRST_DIR} → [路径不存在]"
      fi
    fi
  done
  echo ""
done < <(mount | grep -E "^overlay" 2>/dev/null || echo "${TARGET}")

# --------------------------------------------------------------------------
# B2. 下层文件系统兼容性检查
# --------------------------------------------------------------------------
echo ""
echo "【B2】文件系统兼容性评估"
echo "------------------------------------------------------------------"

# 已知不兼容的 FS
echo "已知不兼容/不推荐用于 upperdir 的文件系统："
echo "  fuse（s3fs/glusterfs/sshfs 等）— upperdir 不支持（d_type 缺失）"
echo "  NFS（远程挂载）— upperdir 不推荐（性能与稳定性问题）"
echo "  FAT32/exFAT/NTFS — 不支持 xattr，不能作为 upperdir"
echo "  tmpfs — 可作为 upperdir 但重启丢失"
echo "  ZFS（某些配置）— 需验证 xattr 支持"
echo ""

echo "推荐用于 upperdir 的文件系统："
echo "  ext4 (✓ xattr ✓ d_type)"
echo "  xfs (✓ xattr ✓ d_type — 建议创建时启用 ftype=1)"
echo "  btrfs (✓ xattr ✓ d_type)"
echo ""

# 检查具体 FS 是否支持 d_type
echo "当前各层 d_type 支持情况："
while IFS= read -r line; do
  OPTIONS=$(echo "$line" | awk -F ' - ' '{print $2}' 2>/dev/null || echo "$line")
  for dir_param in "upperdir" "lowerdir"; do
    DIR_VAL=$(echo "$OPTIONS" | grep -oP "${dir_param}=\K[^, ]+" 2>/dev/null || true)
    if [[ -n "${DIR_VAL}" ]]; then
      FIRST_DIR=$(echo "${DIR_VAL}" | cut -d':' -f1)
      if [[ -e "${FIRST_DIR}" ]]; then
        FS_TYPE=$(df -hT "${FIRST_DIR}" 2>/dev/null | tail -1 | awk '{print $2}')
        # 检测 d_type 支持：在目录中创建文件并 stat
        TEST_FILE="${FIRST_DIR}/.d_type_test_$(date +%s)"
        touch "${TEST_FILE}" 2>/dev/null || true
        if [[ -f "${TEST_FILE}" ]]; then
          DTYPE=$(stat -c "%F" "${TEST_FILE}" 2>/dev/null)
          rm -f "${TEST_FILE}" 2>/dev/null || true
          echo "  ${FS_TYPE} (${FIRST_DIR}): d_type ✓（文件类型正确解析）"
        else
          echo "  ${FS_TYPE} (${FIRST_DIR}): d_type ⚠️（无法确认，可能不受支持）"
        fi
      fi
    fi
  done
done < <(mount | grep -E "^overlay" 2>/dev/null || true)

# --------------------------------------------------------------------------
# B3. Docker 特定检查（容器场景）
# --------------------------------------------------------------------------
if command -v docker &>/dev/null && [[ -n "${CONTAINER}" ]]; then
  echo ""
  echo "【B3】Docker overlay2 兼容性检查"
  echo "------------------------------------------------------------------"
  docker info 2>/dev/null | grep -i "storage\|backing" || echo "  无法获取 Docker 存储信息"

  if [[ -f /var/lib/docker/overlay2/backingFsBlockDev ]]; then
    echo "  后备块设备: $(cat /var/lib/docker/overlay2/backingFsBlockDev)"
  fi
fi

# --------------------------------------------------------------------------
# B4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【B4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

根据文件系统类型选择对应的措施：

问题1：upperdir 在 fuse/NFS 上
  修复：
    将 upperdir 迁移到本地文件系统（ext4/xfs）
    ⚠️ Docker overlay2 的 /var/lib/docker 目录必须在本地文件系统上

问题2：upperdir 在 FAT/NTFS 上（常见于外置存储）
  修复：
    换用 ext4/xfs/btrfs：
    mkfs.ext4 /dev/sdX
    mount /dev/sdX /upper

问题3：xfs 未启用 ftype=1（d_type 缺失）
  确认：
    xfs_info /mount/point | grep ftype
  修复：
    需要重新格式化 xfs 时启用 -n ftype=1：
    mkfs.xfs -n ftype=1 /dev/sdX

问题4：docker overlay2 后备文件系统不兼容
  修复：
    将 /var/lib/docker 迁移到兼容的文件系统
    停止 docker → 迁移数据 → 修改 docker 配置 → 重启 docker
FIX_SUGGESTIONS
