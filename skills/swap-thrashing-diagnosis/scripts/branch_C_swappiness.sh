#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_swappiness.sh
# 用途：Swappiness 配置不当诊断
# 使用：bash branch_C_swappiness.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支C：Swappiness 配置不当 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 - 当前 swappiness 值
# --------------------------------------------------------------------------
echo ""
echo "【M1】当前 swappiness 配置"
echo "------------------------------------------------------------------"

SWAPPINESS=$(sysctl vm.swappiness 2>/dev/null | awk '{print $3}' || echo 60)
echo "  vm.swappiness = ${SWAPPINESS}"
echo ""

echo "  分类:"
if [ "$SWAPPINESS" -eq 0 ]; then
  echo "  · ✅ swappiness=0（禁用 swap 倾向——但内核仍可能在极端情况下 swap）"
elif [ "$SWAPPINESS" -le 10 ]; then
  echo "  · 低 swappiness（1-10）：适合数据库/延迟敏感场景"
elif [ "$SWAPPINESS" -le 60 ]; then
  echo "  · 中等 swappiness（11-60）：通用场景"
elif [ "$SWAPPINESS" -le 100 ]; then
  echo "  · 高 swappiness（61-100）：偏向匿名页 swap out"
else
  echo "  · 极高 swappiness（>100）：极其激进地 swap out 匿名页"
fi

echo ""

# --------------------------------------------------------------------------
# M2 - swappiness 对系统的影响评估
# --------------------------------------------------------------------------
echo ""
echo "【M2】影响评估"
echo "------------------------------------------------------------------"

MEMINFO="${OUT_DIR}/meminfo.txt"
CACHED=$(awk '/^Cached:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0)
DIRTY=$(awk '/^Dirty:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0)
SWAP_TOTAL=$(awk '/^SwapTotal:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0)
SWAP_USED=$(( SWAP_TOTAL - $(awk '/^SwapFree:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0) ))

echo "  Page Cache: ${CACHED} kB"
echo "  脏页:       ${DIRTY} kB"
echo "  Swap 已用:  ${SWAP_USED} kB / ${SWAP_TOTAL} kB"
echo ""

if [ "$SWAPPINESS" -gt 60 ]; then
  echo "  ⚠ 分析: swappiness=${SWAPPINESS} 偏高"
  if [ "$CACHED" -gt "$DIRTY" ] && [ "$SWAP_USED" -gt 0 ]; then
    echo "    · 文件页缓存充足但仍在 swap out → swappiness 过高"
    echo "    · 建议降低到 10-30 之间"
  fi
elif [ "$SWAPPINESS" -eq 0 ]; then
  echo "  ⚠ 分析: swappiness=0"
  echo "    · 这是一个常见的误解设置"
  echo "    · swappiness=0 不会完全禁用 swap"
  echo "    · 在内存压力大时内核仍然会 swap out"
  echo "    · 如果需要真正禁用某个 cgroup 的 swap:"
  echo "      echo 0 > /sys/fs/cgroup/<path>/memory.swappiness"
elif [ "$SWAPPINESS" -le 10 ]; then
  echo "  ✓ 分析: swappiness=${SWAPPINESS} 适合延迟敏感场景"
  if [ "$SWAP_USED" -gt 0 ] && [ "$CACHED" -gt 0 ]; then
    echo "    · 但仍存在 swap 活动 → 检查是否有其他因素"
    echo "    · 检查 dirty 页是否占用了大量文件页缓存"
  fi
fi

# --------------------------------------------------------------------------
# M3 - 内核语义分析
# --------------------------------------------------------------------------
echo ""
echo "【M3】内核 swappiness 机制分析"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  swappiness 的工作机制:

  shrink_lruvec() 在 mm/vmscan.c 中计算扫描比例:

    anon_priority = swappiness
    file_priority = 200 - swappiness  /* 反向关系 */
    
    扫描比例 = anon_priority / (anon_priority + file_priority)
            = swappiness / (swappiness + 200 - swappiness)
            = swappiness / 200
  
  举例:
    swappiness=60  → 匿名页扫描概率 = 60/200 = 30%
    swappiness=10  → 匿名页扫描概率 = 10/200 = 5%
    swappiness=1   → 匿名页扫描概率 = 1/200  = 0.5%
    swappiness=0   → 匿名页扫描概率 = 0%（但直接回收时仍可能 swap）

  注意点:
    · swappiness 是"倾向性"，不是"硬开关"
    · 当文件页不可回收时（脏页、被锁页），即使 swappiness=0 也需要 swap
    · cgroup 级别的 memory.swappiness 才能真正禁用 cgroup 内的 swap
SRCGUIDE

echo ""
echo "【根因排查与建议】"
echo "------------------------------------------------------------------"

if [ "$SWAPPINESS" -gt 100 ]; then
  echo "  🔴 严重配置不当: swappiness=${SWAPPINESS} > 100"
  echo "  建议: sysctl -w vm.swappiness=60（恢复默认）"
  echo "        或根据场景设为 10-30"
elif [ "$SWAPPINESS" -gt 60 ]; then
  echo "  🟡 建议优化: swappiness=${SWAPPINESS} 偏高"
  echo "  推荐设置:"
  echo "    · 通用服务器: sysctl -w vm.swappiness=60"
  echo "    · 数据库:     sysctl -w vm.swappiness=10"
  echo "    · Java 应用:  sysctl -w vm.swappiness=10-30"
  echo "    · 高 IO 负载: sysctl -w vm.swappiness=1-10"
  echo "    · 实时系统:   sysctl -w vm.swappiness=1"
elif [ "$SWAPPINESS" -eq 0 ]; then
  echo "  🟡 注意: swappiness=0 不会完全禁用 swap"
  echo "  如果需要真正禁用某个 cgroup 的 swap:"
  echo "    echo 0 > /sys/fs/cgroup/<cgroup_path>/memory.swappiness"
  echo "  如果需要全局最小化 swap:"
  echo "    echo 1 > /proc/sys/vm/swappiness"
else
  echo "  ✓ swappiness=${SWAPPINESS} 在合理范围内"
  echo "  如果仍有 swap 问题，请检查其他因素（如脏页比例、工作集大小）"
fi

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: Swappiness 配置不当
  当前值: ${SWAPPINESS}
  建议值: 根据负载类型推荐 10-60 之间
  
  处理建议:
    【临时调整】
      sysctl -w vm.swappiness=<推荐值>
      # 持久化: 写入 /etc/sysctl.conf 或 /etc/sysctl.d/
    
    【验证建议】
      - 调整后使用 01_baseline_info.sh 复测
      - 观察 si/so 速率是否下降
      - 确认应用性能是否有改善
CONCLUSION
