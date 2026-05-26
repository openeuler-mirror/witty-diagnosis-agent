#!/usr/bin/env bash
# =============================================================================
# 脚本：02_diagnosis.sh —— Swap Thrashing 诊断执行器
# 用途：运行基线信息收集 → 根据分支推荐 → 自动调度对应分支脚本执行
# 使用：bash 02_diagnosis.sh [output_dir]
# 参数：
#   $1  输出目录（可选，默认 /tmp/swap_diag_<timestamp>）
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " Swap Thrashing 诊断执行器"
echo " 脚本目录: ${SCRIPT_DIR}"
echo " 输出目录: ${OUT_DIR}"
echo " 时间: $(date)"
echo "=================================================================="
echo ""

# Step 1: 基线信息收集
echo "=== Step 1: 基线信息收集 ==="
bash "${SCRIPT_DIR}/01_baseline_info.sh" "${OUT_DIR}"
echo ""

# Step 2: 解析分支推荐，自动执行
echo "=== Step 2: 解析分支推荐 ==="
RECOMMEND="${OUT_DIR}/branch_recommendation.txt"
BRANCHES=$(grep "^.* → bash " "${RECOMMEND}" 2>/dev/null || true)

if [ -z "${BRANCHES}" ]; then
  echo "  未检测到分支推荐，执行通用 thrashing 检测..."
  echo ""

  # 执行分支 B（Thrashing 检测，最通用）
  if [ -f "${SCRIPT_DIR}/scripts/branch_B_thrashing.sh" ] || [ -f "${SCRIPT_DIR}/branch_B_thrashing.sh" ]; then
    BRANCH_SCRIPT="${SCRIPT_DIR}/scripts/branch_B_thrashing.sh"
    [ ! -f "$BRANCH_SCRIPT" ] && BRANCH_SCRIPT="${SCRIPT_DIR}/branch_B_thrashing.sh"
    echo "--- 执行: thrashing 检测 ---"
    bash "${BRANCH_SCRIPT}" "${OUT_DIR}"
  fi
else
  echo "  检测到分支推荐:"
  echo "${BRANCHES}"
  echo ""

  # 推荐优先级高的先执行
  # 按严重程度排序: A(耗尽) > B(thrashing) > F(kswapd) > D(损坏) > G(zswap) > C(swappiness) > E(SSD)
  PRIORITY_ORDER="branch_A branch_B branch_F branch_D branch_G branch_C branch_E"

  BRANCH_NAMES=$(echo "${BRANCHES}" | grep -oP 'branch_[A-Z]')

  for prefix in ${PRIORITY_ORDER}; do
    match=$(echo "${BRANCHES}" | grep "${prefix}" || true)
    if [ -n "${match}" ]; then
      BRANCH_SCRIPT=$(echo "${match}" | grep -oP 'scripts/\S+' || true)
      [ -z "${BRANCH_SCRIPT}" ] && BRANCH_SCRIPT=$(echo "${match}" | grep -oP "bash \K\S+" || true)

      if [ -n "${BRANCH_SCRIPT}" ]; then
        # 脚本路径可以是相对于 02_diagnosis.sh 的路径
        if [[ "${BRANCH_SCRIPT}" != /* ]]; then
          BRANCH_SCRIPT="${SCRIPT_DIR}/${BRANCH_SCRIPT}"
        fi
        if [ -f "${BRANCH_SCRIPT}" ]; then
          echo "--- 执行: ${prefix} ---"
          bash "${BRANCH_SCRIPT}" "${OUT_DIR}"
          echo ""
        else
          echo "  脚本不存在: ${BRANCH_SCRIPT} (跳过)"
        fi
      fi
    fi
  done
fi

# Step 3: 生成汇总报告
echo "=== Step 3: 汇总报告 ==="

{
  echo "=================================================================="
  echo " Swap Thrashing 诊断汇总报告"
  echo " 时间: $(date)"
  echo " 输出目录: ${OUT_DIR}"
  echo "=================================================================="
  echo ""

  echo "【已执行的分析】"
  [ -f "${OUT_DIR}/branch_recommendation.txt" ] && grep "✓\|🔴\|🟡" "${OUT_DIR}/branch_recommendation.txt" 2>/dev/null || echo "  无分支匹配记录"

  echo ""
  echo "【输出文件清单】"
  ls -lh "${OUT_DIR}/" 2>/dev/null | grep -v "^total" | awk '{print "  " $NF " (" $5 ")"}'

  echo ""
  echo "【关键指标摘要】"
  [ -f "${OUT_DIR}/meminfo.txt" ] && grep -E "SwapTotal|SwapFree|MemTotal|MemFree|MemAvailable|Dirty|Writeback" "${OUT_DIR}/meminfo.txt" 2>/dev/null
  [ -f "${OUT_DIR}/vm_key_metrics.txt" ] && cat "${OUT_DIR}/vm_key_metrics.txt" 2>/dev/null

  echo ""
  echo "【下一步建议】"
  echo "  1. 阅读分支脚本输出确认具体根因"
  echo "  2. 如有源码，可参考 SKILL.md 第四节（内核语义分析）进行源码级追踪"
  echo "  3. 如已完成全部分析，按 SKILL.md 第九节模板撰写最终报告"
  echo "=================================================================="
} > "${OUT_DIR}/diagnosis_report.txt" 2>/dev/null

cat "${OUT_DIR}/diagnosis_report.txt"
