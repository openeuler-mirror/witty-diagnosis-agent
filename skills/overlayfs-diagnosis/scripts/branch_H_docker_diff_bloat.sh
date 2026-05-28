#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_H_docker_diff_bloat.sh
# 用途：Docker overlay2 diff 目录膨胀诊断
# 场景：/var/lib/docker/overlay2 持续膨胀，远超镜像大小
# 使用：bash branch_H_docker_diff_bloat.sh [threshold_gb]
# =============================================================================

set -euo pipefail

THRESHOLD_GB="${1:-10}"

echo "=================================================================="
echo " 分支H：Docker overlay2 diff 目录膨胀诊断"
echo " 警告阈值: ${THRESHOLD_GB}GB"
echo "=================================================================="

# --------------------------------------------------------------------------
# H1. Overlay2 总体空间分析
# --------------------------------------------------------------------------
echo ""
echo "【H1】Overlay2 总体空间使用"
echo "------------------------------------------------------------------"

OVERLAY2_DIR="/var/lib/docker/overlay2"
if [[ ! -d "${OVERLAY2_DIR}" ]]; then
  echo "  ${OVERLAY2_DIR} 不存在或无权限。尝试检查 /var/lib/docker..."
  if [[ -d /var/lib/docker ]]; then
    du -sh /var/lib/docker 2>/dev/null
  else
    echo "  Docker 数据目录不可访问。"
    exit 1
  fi
fi

TOTAL_SIZE=$(du -sh "${OVERLAY2_DIR}" 2>/dev/null | awk '{print $1}')
TOTAL_SIZE_BYTES=$(du -sb "${OVERLAY2_DIR}" 2>/dev/null | awk '{print $1}')
echo "overlay2 总大小: ${TOTAL_SIZE}"
echo "overlay2 总 inode: $(find "${OVERLAY2_DIR}" -xdev 2>/dev/null | wc -l)"

# --------------------------------------------------------------------------
# H2. 各层大小详细分析
# --------------------------------------------------------------------------
echo ""
echo "【H2】各容器层大小排名"
echo "------------------------------------------------------------------"

echo "Top 20 最大的 diff 目录："
# 使用 find 替代 du 的并行统计
for layer in "${OVERLAY2_DIR}"/*/; do
  if [[ -d "${layer}/diff" ]]; then
    LAYER_SIZE=$(du -sb "${layer}/diff" 2>/dev/null | awk '{print $1}' || echo 0)
    LAYER_FILE_COUNT=$(find "${layer}/diff" -type f 2>/dev/null | wc -l || echo 0)
    LAYER_DIR_COUNT=$(find "${layer}/diff" -type d 2>/dev/null | wc -l || echo 0)
    HASH=$(basename "${layer}")
    echo "${LAYER_SIZE} ${HASH:0:12}... 文件:${LAYER_FILE_COUNT} 目录:${LAYER_DIR_COUNT}"
  fi
done | sort -rn | head -20 | while IFS= read -r line; do
  SIZE=$(echo "$line" | awk '{print $1}')
  REST=$(echo "$line" | cut -d' ' -f2-)
  HUMAN=$(numfmt --to=iec <<< "${SIZE}" 2>/dev/null || echo "${SIZE}")
  echo "  ${HUMAN}  ${REST}"
done

# --------------------------------------------------------------------------
# H3. Diff 目录内容结构分析
# --------------------------------------------------------------------------
echo ""
echo "【H3】Diff 目录内容分析（Top 3 最大层）"
echo "------------------------------------------------------------------"

# 找到最大的 3 个 diff 目录
TOP_LAYERS=$(for layer in "${OVERLAY2_DIR}"/*/; do
  [[ -d "${layer}/diff" ]] && echo "$(du -sb "${layer}/diff" 2>/dev/null | awk '{print $1}') ${layer}"
done | sort -rn | head -3 | awk '{print $2}')

for layer_path in ${TOP_LAYERS}; do
  HASH=$(basename "${layer_path}")
  DIFF_DIR="${layer_path}/diff"
  echo "--- ${HASH:0:12}... ---"
  echo "  文件类型分布："
  find "${DIFF_DIR}" -type f 2>/dev/null | awk -F. '{if(NF>1) print tolower($NF); else print "(no_ext)"}' | \
    sort | uniq -c | sort -rn | head -10
  echo "  最大子目录 Top 5："
  du -sh "${DIFF_DIR}"/*/ 2>/dev/null | sort -rh | head -5
  echo "  Whiteout 文件数: $(find "${DIFF_DIR}" -name ".wh.*" 2>/dev/null | wc -l)"
  echo ""
done

# --------------------------------------------------------------------------
# H4. Docker 系统整体分析
# --------------------------------------------------------------------------
echo ""
echo "【H4】Docker 系统整体状态"
echo "------------------------------------------------------------------"

if command -v docker &>/dev/null; then
  docker system df 2>/dev/null || echo "  Docker 不可用"

  echo ""
  echo "各容器实际大小（含 diff 层）："
  docker ps -a --size --format "table {{.ID}}\t{{.Names}}\t{{.Size}}\t{{.Status}}" 2>/dev/null | head -30

  echo ""
  echo "BuildKit 缓存大小："
  du -sh /var/lib/docker/buildkit/ 2>/dev/null || echo "  （无 buildkit 缓存）"

  echo ""
  echo "容器日志文件大小："
  ls -lh /var/lib/docker/containers/*/*-json.log 2>/dev/null | \
    awk '{print $5, $NF}' | sort -rh | head -10 || echo "  （无日志文件）"
fi

# --------------------------------------------------------------------------
# H5. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【H5】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

Diff 目录膨胀处理流程（按推荐顺序）：

Step 1: 清理未使用的容器和镜像
  docker container prune                    # 清理停止的容器
  docker image prune -a                     # 清理未使用的镜像
  docker builder prune --all                # 清理 build 缓存
  docker system df                          # 验证释放的空间

Step 2: 检查并限制日志
  # 配置日志轮转（全局）
  vim /etc/docker/daemon.json
  {
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "10m",
      "max-file": "3"
    }
  }
  systemctl restart docker   # 重启后，旧容器仍保留旧日志，新容器使用新配置

  # 清理现有容器日志（重建容器是唯一干净方式）
  # 或手动 truncate：
  truncate -s 0 /var/lib/docker/containers/*/*-json.log

Step 3: 检查是否有遗留数据
  # 查看 /var/lib/docker/overlay2 中哪些目录没有对应容器
  # 技巧：比较 overlay2 子目录与容器 GraphDriver 中引用的层

Step 4: 长期策略
  - 限制容器日志大小（见 Step 2）
  - 将写密集型数据放在 volume 中（非容器层）
  - 定期执行 docker system prune
  - 监控 /var/lib/docker 大小，设置告警

Step 5: 极端措施（重新初始化）
  ⚠️ 会丢失所有容器和镜像数据！
  systemctl stop docker
  rm -rf /var/lib/docker/overlay2
  systemctl start docker
  # 然后重新拉取镜像、启动容器
FIX_SUGGESTIONS
