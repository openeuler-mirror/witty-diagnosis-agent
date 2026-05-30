#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_library_trace.sh
# 用途：库函数调用链异常追踪 — 双轨分析
# 使用：bash branch_C_library_trace.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"
DURATION="${2:-15}"

echo "=================================================================="
echo " 分支C：库函数调用链异常追踪 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# T1 - ltrace 采集
# --------------------------------------------------------------------------
echo ""
echo "【T1】ltrace 库函数调用"
echo "------------------------------------------------------------------"

# 尝试从基线获取 PID
BASELINE_TARGET="${OUT_DIR}/process_status.txt"
TARGET_PID=""
if grep -q "^Pid:" "$BASELINE_TARGET" 2>/dev/null; then
  TARGET_PID=$(grep "^Pid:" "$BASELINE_TARGET" | awk '{print $2}')
fi

if command -v ltrace &>/dev/null; then
  if [ -n "$TARGET_PID" ] && kill -0 "$TARGET_PID" 2>/dev/null; then
    echo "  采集 ltrace (PID=$TARGET_PID, ${DURATION}s)..."
    timeout "${DURATION}" ltrace -T -n 2 -p "${TARGET_PID}" 2>/dev/null | \
      head -200 > "${OUT_DIR}/ltrace_raw.txt" 2>/dev/null || true
    echo "  -> ltrace_raw.txt"
  else
    echo "  PID 不可用，跳过 ltrace 自动采集"
    echo "  可手动运行: ltrace -T -n 2 -p <PID>"
  fi
else
  echo "  ltrace 不可用，请先安装: apt install ltrace / yum install ltrace"
fi

echo ""

# --------------------------------------------------------------------------
# T2 - ltrace 统计分析
# --------------------------------------------------------------------------
echo ""
echo "【T2】库函数调用分析"
echo "------------------------------------------------------------------"

LTRACE_FILE="${OUT_DIR}/ltrace_raw.txt"
if [ -f "$LTRACE_FILE" ]; then
  TOTAL_LINES=$(wc -l < "$LTRACE_FILE")
  echo "  总调用行数: ${TOTAL_LINES}"

  # 按函数名统计频次
  echo ""
  echo "  Top 高频库函数:"
  grep -oP "^[A-Za-z_][A-Za-z0-9_]*" "$LTRACE_FILE" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -15 || echo "    (无)"

  # 按耗时排序
  echo ""
  echo "  Top 最慢库函数（按平均耗时）:"
  awk -F'<' 'NF>1 && $2 ~ /^[0-9]+\.[0-9]+>/ {
    gsub(/>.*/, "", $2);
    funcname=$1;
    gsub(/^[ \t]+/, "", funcname);
    gsub(/\(.*/, "", funcname);
    total[funcname] += $2;
    count[funcname] += 1;
  } END {
    for (f in total) {
      avg = total[f] / count[f];
      printf "%s %.3f %d\n", f, avg, count[f];
    }
  }' "$LTRACE_FILE" 2>/dev/null | sort -k2 -rn | head -15 || echo "    (无)"

  # 调用深度分析
  echo ""
  echo "  调用深度分布:"
  awk '{match($0, /^[| ]+/); depth=length(substr($0, RSTART, RLENGTH))/2; print depth}' \
    "$LTRACE_FILE" 2>/dev/null | sort -rn | awk '
    {if(NR==1) max=$1; if($1>0) sum++}
    END{printf "    最大深度: %d, 总调用帧: %d\n", max, sum}' || true
fi

echo ""

# --------------------------------------------------------------------------
# T3 - 关联 syscall 分析
# --------------------------------------------------------------------------
echo ""
echo "【T3】库函数 ↔ syscall 对照分析"
echo "------------------------------------------------------------------"
if [ -f "$LTRACE_FILE" ] && [ -f "${OUT_DIR}/strace_all.txt" ]; then
  # 检查 malloc/free 热点
  echo "  malloc/free 热点:"
  grep -c "malloc" "$LTRACE_FILE" 2>/dev/null && echo "    malloc 调用次数: $(grep -c "malloc" $LTRACE_FILE 2>/dev/null)" || echo "    (无)"
  grep -c "free" "$LTRACE_FILE" 2>/dev/null && echo "    free 调用次数: $(grep -c "free" $LTRACE_FILE 2>/dev/null)" || echo "    (无)"
  grep -c "realloc" "$LTRACE_FILE" 2>/dev/null && echo "    realloc 调用次数: $(grep -c "realloc" $LTRACE_FILE 2>/dev/null)" || echo "    (无)"
fi

echo ""

# --------------------------------------------------------------------------
# T4 - 独立归因
# --------------------------------------------------------------------------
echo ""
echo "【T4】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  echo "  库函数热点: 已生成"
  echo "  调用轨迹归因假设: 基于库函数调用频次和耗时分析"
} | tee -a "${OUT_DIR}/branch_C_metrics.txt"

# ==========================================================================
# ▶ 内核语义轨道
# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道 —— 库函数异常分析"
echo "=================================================================="

echo ""
echo "【K1】常见库函数异常模式"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  malloc/free 频繁:
    · 检查是否在热路径中分配临时对象
    · 使用内存池或对象复用
    · 考虑 jemalloc/tcmalloc

  库函数路径异常:
    · 检查 LD_PRELOAD 是否劫持了函数
    · 检查库版本: ldd <binary> | grep libc
    · 检查符号版本: nm -D <library> | grep <func>

  耗时异常:
    · 区分库函数自身耗时 vs 内部 syscall 耗时
    · 使用 ltrace -S 同时显示库函数和 syscall 的对应关系
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 库函数调用链异常
  处理建议:
    · 内存操作频繁 → 使用内存池或缓存
    · 调用路径异常 → 检查库版本和 LD_PRELOAD
    · 库函数耗时高 → 检查对应 syscall 耗时（切换 strace 定位）
    
    【验证建议】
      - 使用 ltrace -S 关联库函数和 syscall
      - 对比不同版本库函数行为差异
CONCLUSION
