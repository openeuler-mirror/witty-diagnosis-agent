#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_K_readdir_perf.sh
# 用途：OverlayFS 目录读性能诊断（readdir 合并开销）
# 场景：overlay + 容器场景下磁盘 I/O 异常高；ls /merged 非常慢；directory traversal 慢
# 使用：bash branch_K_readdir_perf.sh [mount_point]
# =============================================================================

set -euo pipefail

TARGET="${1:-}"

echo "=================================================================="
echo " 分支K：OverlayFS 目录读性能诊断"
echo "=================================================================="

# --------------------------------------------------------------------------
# K1. 目录深度与文件数量分析
# --------------------------------------------------------------------------
echo ""
echo "【K1】目录深度与文件数量分析"
echo "------------------------------------------------------------------"

if [[ -z "${TARGET}" || ! -d "${TARGET}" ]]; then
  TARGET=$(mount | grep overlay | head -1 | awk '{print $3}')
fi

if [[ -n "${TARGET}" ]]; then
  echo "分析挂载点: ${TARGET}"

  # 目录深度分析
  echo ""
  echo "目录深度分布："
  find "${TARGET}" -type d 2>/dev/null | awk -F/ '{print NF-1}' | sort -n | uniq -c | sort -rn | head -15

  # 整体统计
  TOTAL_DIRS=$(find "${TARGET}" -type d 2>/dev/null | wc -l)
  TOTAL_FILES=$(find "${TARGET}" -type f 2>/dev/null | wc -l)
  echo ""
  echo "总目录数: ${TOTAL_DIRS}"
  echo "总文件数: ${TOTAL_FILES}"

  # 单目录最大文件数
  echo ""
  echo "文件最密集的目录（Top 10）："
  find "${TARGET}" -type d 2>/dev/null | while IFS= read -r d; do
    COUNT=$(find "${d}" -maxdepth 1 -type f 2>/dev/null | wc -l)
    if [[ "${COUNT}" -gt 10 ]]; then
      echo "${COUNT} ${d}"
    fi
  done | sort -rn | head -10
fi

# --------------------------------------------------------------------------
# K2. Layer 对比分析（lower vs upper 文件分布）
# --------------------------------------------------------------------------
echo ""
echo "【K2】Layer 对比分析"
echo "------------------------------------------------------------------"

# 获取 upperdir 路径
UPPER_DIRS=$(mount | grep overlay | grep -oP 'upperdir=[^, ]+' | cut -d'=' -f2 2>/dev/null || true)
LOWER_DIRS=$(mount | grep overlay | grep -oP 'lowerdir=[^, ]+' | cut -d'=' -f2 2>/dev/null || true)

if [[ -n "${UPPER_DIRS}" ]]; then
  echo "upperdir 文件数: $(find "${UPPER_DIRS}" -type f 2>/dev/null | wc -l)"
  echo "upperdir 目录数: $(find "${UPPER_DIRS}" -type d 2>/dev/null | wc -l)"
fi

if [[ -n "${LOWER_DIRS}" ]]; then
  echo ""
  echo "lowerdir 各层规模："
  IFS=':' read -ra LOWERS <<< "${LOWER_DIRS}"
  for i in "${!LOWERS[@]}"; do
    LP="${LOWERS[$i]}"
    if [[ -e "${LP}" ]]; then
      echo "  [${i}] $(basename ${LP}): $(find "${LP}" -type f 2>/dev/null | wc -l) 文件, $(find "${LP}" -type d 2>/dev/null | wc -l) 目录"
    fi
  done
fi

# --------------------------------------------------------------------------
# K3. 性能基准测试
# --------------------------------------------------------------------------
echo ""
echo "【K3】目录遍历性能测试"
echo "------------------------------------------------------------------"

if [[ -n "${TARGET}" ]]; then
  echo "测试1: ls -la 耗时（根目录）"
  TIMEFORMAT="  real %3R  user %3U  sys %3S"
  time ls -la "${TARGET}" 2>/dev/null 1>/dev/null

  echo ""
  echo "测试2: find 文件总数耗时"
  TIMEFORMAT="  real %3R  user %3U  sys %3S"
  time find "${TARGET}" -type f 2>/dev/null | head -1000 > /dev/null

  # 对比：同目录数在非 overlay 上的性能
  echo ""
  echo "测试3: stat 元数据读取"
  TIMEFORMAT="  real %3R  user %3U  sys %3S"
  time stat "${TARGET}" 2>/dev/null

  # 对比分析：测试文件少的子目录
  SMALL_SUBDIR=$(find "${TARGET}" -type d 2>/dev/null | head -5 | tail -1)
  if [[ -n "${SMALL_SUBDIR}" && "${SMALL_SUBDIR}" != "${TARGET}" ]]; then
    echo ""
    echo "测试4: 子目录（${SMALL_SUBDIR}）ls 耗时"
    TIMEFORMAT="  real %3R  user %3U  sys %3S"
    time ls -la "${SMALL_SUBDIR}" 2>/dev/null 1>/dev/null
  fi
fi

# --------------------------------------------------------------------------
# K4. 内核态机理说明
# --------------------------------------------------------------------------
echo ""
echo "【K4】内核态机理说明"
echo "------------------------------------------------------------------"
cat << 'KERNEL_GUIDE'

OverlayFS readdir 性能模型：

OverlayFS 的目录合并操作（readdir/iterate）需要：

1. 读取 upper 层的目录条目
2. 读取所有 lower 层的目录条目（多层时依次读取）
3. 合并这些条目：
   - 跳过 upper 中的 whiteout 对应的 lower 条目
   - 如有 opaque 标记，跳过所有 lower 条目
   - 处理 redirect 到新的位置

性能瓶颈在于：
  - 每层都需要独立的 readdir 系统调用
  - 条目的合并需要 O(N_upper + N_lower) 的哈希比较
  - 多层 lower 时的累积开销

目录深度的影响：
  - 每访问一层子目录，都需要重复在各层中查找对应目录
  - 目录越深，需要的查找操作越多

large_dir / 百万文件场景：
  - ext4 在目录文件数 > 10K 时，线性查找性能急剧下降
  - xfs 使用 B-tree，但在目录非常大的情况下仍有开销
  - overlay 需要同时扫描 upper + lower，问题被放大

KERNEL_GUIDE

# --------------------------------------------------------------------------
# K5. 修复建议
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " 【K5】修复建议"
echo "=================================================================="
cat << 'FIX_SUGGESTIONS'

OverlayFS 读性能优化策略：

方案1：减少 lower 层数
  - 合并多层 lower 到一层（如果不需要多层隔离）
  - 使用 docker image squash 合并镜像层
  - 平衡：更多 lower 层 = 更灵活，但 readdir 更慢

方案2：优化目录结构
  - 避免单目录存放超过 10K 文件
  - 使用集中目录结构替代深度嵌套
  - 对于深度目录，考虑预先绑定到短路径

方案3：Docker 容器优化
  - 多阶段构建减少镜像层数
  - 将频繁读写的目录挂载为 volume（绕过 overlay）
  - 减少容器 diff 目录中的文件数量
  - 使用 docker export/import 合并层

方案4：使用 xfs 文件系统
  - xfs 的 B-tree 目录结构在大目录场景下优于 ext4 的哈希树
  - 格式化：mkfs.xfs -n ftype=1 /dev/sdX
  - 大目录场景可考虑 large_dir 特性

方案5：内核参数调整
  # no 配置可显著改善，以下为调试参考
  # 使用 tracepoint 分析 readdir 性能瓶颈
  echo 1 > /sys/kernel/debug/tracing/events/syscalls/sys_enter_getdents64/enable
  cat /sys/kernel/debug/tracing/trace_pipe
  # 观察 getdents64 的调用频率和耗时
FIX_SUGGESTIONS
