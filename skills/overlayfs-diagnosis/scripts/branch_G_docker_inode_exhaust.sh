#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_docker_inode_exhaust.sh
# 用途：Docker overlay2 inode 耗尽诊断
# 场景：容器/应用报 "no space left on device" 但 df -h 显示有余量
# 使用：bash branch_G_docker_inode_exhaust.sh
# =============================================================================

set -euo pipefail

echo "=================================================================="
echo " 分支G：Docker overlay2 inode 耗尽诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# G1. Inode 使用率检查
# --------------------------------------------------------------------------
echo ""
echo "【G1】Inode 使用率"
echo "------------------------------------------------------------------"

for dir in /var/lib/docker /var/lib /; do
  if [[ -d "${dir}" ]]; then
    echo "${dir}:"
    df -i "${dir}" 2>/dev/null | tail -1 | awk '{print "  inode " $3 "/" $2 " → " $5 " 已用"}'
  fi
done

# --------------------------------------------------------------------------
# G2. Inode 消耗来源定位
# --------------------------------------------------------------------------
echo ""
echo "【G2】Inode 消耗来源定位"
echo "------------------------------------------------------------------"

OVERLAY2_DIR="/var/lib/docker/overlay2"
if [[ -d "${OVERLAY2_DIR}" ]]; then
  echo "overlay2 目录 inode 统计："
  echo "  总文件数（递归）: $(find "${OVERLAY2_DIR}" -xdev -type f 2>/dev/null | wc -l)"
  echo "  总目录数（递归）: $(find "${OVERLAY2_DIR}" -xdev -type d 2>/dev/null | wc -l)"

  # 按子目录统计
  echo ""
  echo "各层 inode 消耗 Top 15："
  for layer_dir in "${OVERLAY2_DIR}"/*/diff/; do
    if [[ -d "${layer_dir}" ]]; then
      HASH=$(basename $(dirname "${layer_dir}"))
      FCOUNT=$(find "${layer_dir}" -xdev -type f 2>/dev/null | wc -l)
      DCOUNT=$(find "${layer_dir}" -xdev -type d 2>/dev/null | wc -l)
      SIZE=$(du -sh "${layer_dir}" 2>/dev/null | awk '{print $1}')
      echo "  ${HASH:0:12}... → ${SIZE} | ${FCOUNT} 文件, ${DCOUNT} 目录"
    fi
  done | sort -t'→' -k2 -rh | head -15

  # Whiteout 统计
  echo ""
  echo "Whiteout 文件统计："
  echo "  传统 .wh. 文件数: $(find "${OVERLAY2_DIR}" -name ".wh.*" 2>/dev/null | wc -l)"
  WH_XATTR_COUNT=$(find "${OVERLAY2_DIR}" -exec getfattr -d -m trusted.overlay.whiteout {} \; 2>/dev/null | grep -c "trusted.overlay.whiteout" || echo 0)
  echo "  xattr whiteout 数: ${WH_XATTR_COUNT}"

  # 空目录统计
  echo ""
  echo "空目录数（可能可清理）: $(find "${OVERLAY2_DIR}" -xdev -type d -empty 2>/dev/null | wc -l)"
else
  echo "  overlay2 目录不存在或无权限访问。"
  echo "  尝试检查其他可能 inode 耗尽的位置："
  df -i 2>/dev/null | grep -v "Filesystem" | awk '$5 ~ /^[8-9][0-9]|100/ {print $0}'
fi

# --------------------------------------------------------------------------
# G3. Docker 容器状态
# --------------------------------------------------------------------------
echo ""
echo "【G3】Docker 容器与层状态"
echo "------------------------------------------------------------------"

if command -v docker &>/dev/null; then
  echo "运行中容器数: $(docker ps -q 2>/dev/null | wc -l || echo 0)"
  echo "所有容器数（含停止）: $(docker ps -aq 2>/dev/null | wc -l || echo 0)"
  echo "镜像数: $(docker images -q 2>/dev/null | wc -l || echo 0)"
  echo "未使用的镜像层数: $(docker system df 2>/dev/null | grep "Images" | awk '{print $4}' || echo 'N/A')"

  echo ""
  echo "停止的容器列表（是否可清理？）:"
  docker ps -a --filter "status=exited" --format "  {{.ID}} {{.Names}} ({{.Status}})" 2>/dev/null | head -20 || echo "  无"
else
  echo "  Docker 未安装或不可用。"
fi

# --------------------------------------------------------------------------
# G4. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【G4】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

Inode 耗尽应对措施（按风险从低到高）：

措施1：清理 Docker 未使用资源
  docker container prune          # 删除所有停止的容器
  docker image prune -a           # 删除未使用的镜像
  docker volume prune             # 删除未使用的 volume
  docker system prune -a --volumes # 一键清理所有未使用资源

措施2：检查并清理 whiteout（不删除容器，仅在紧急情况下）
  ⚠️ 注意：删除 whiteout 会让 lower 中已删除的文件重新出现
  仅当确认不需要这些删除"遮挡"时执行：
  # find /var/lib/docker/overlay2 -name ".wh.*" -delete
  # 或更精确：针对已删除容器的残留
  # 参考：docker container prune 后再执行

措施3：扩展 inode 容量
  # ext4 在格式化时指定 inode 数量
  # 查看当前 inode 密度：
  dumpe2fs -h /dev/sda1 | grep -i "inode" | head -5
  # 无法动态增加 inode——需要重新格式化

措施4：迁移 /var/lib/docker 到 inode 更充裕的分区
  systemctl stop docker
  # 迁移
  rsync -a /var/lib/docker/ /new/location/docker/
  # 配置 daemon.json
  echo '{"data-root": "/new/location/docker"}' > /etc/docker/daemon.json
  systemctl start docker

措施5：调整 Docker 日志限制（减少日志文件数量，间接减少 inode 消耗）
  # 在 /etc/docker/daemon.json 中配置：
  {
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "10m",
      "max-file": "3"
    }
  }
  # 重启 Docker 生效
FIX_SUGGESTIONS
