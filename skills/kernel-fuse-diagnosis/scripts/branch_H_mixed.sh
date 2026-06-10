#!/bin/bash
# branch_H_mixed.sh — FUSE 混合/复杂故障诊断
# 场景: 多种现象共存，或以上分支无法覆盖的复杂 FUSE 问题
# 对应 SKILL.md Branch H
#
# Usage: bash branch_H_mixed.sh <mount_point> [daemon_pid]

MOUNT_POINT="${1:-}"
DAEMON_PID="${2:-}"
REPORT_DIR="${3:-/tmp/fuse_mixed_report}"
mkdir -p "$REPORT_DIR"

echo "============================================"
echo " Branch H: 混合/复杂 FUSE 故障诊断"
echo "============================================"
echo "  挂载点: ${MOUNT_POINT:-未指定}"
echo "  PID: ${DAEMON_PID:-未指定}"
echo "  报告目录: $REPORT_DIR"
echo ""

# ---- L2: 类型层诊断（全量采集） ----

# 1. 所有分支的 L2 诊断汇总
echo "--- [L2-1] 汇总基线 ---"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  主机: $(hostname)"
echo "  内核: $(uname -r)"
echo ""

# 2. 完整 strace 追踪
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-2] strace 全系统调用追踪 (10 秒) ---"
    timeout 10 strace -f -e trace=all -p "$DAEMON_PID" -c 2>&1 | tee "$REPORT_DIR/strace_summary.txt"
    echo "  strace 已保存到 $REPORT_DIR/strace_summary.txt"
    echo ""
fi

# 3. daemon 打开的文件
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-3] lsof daemon 打开文件 ---"
    lsof -p "$DAEMON_PID" 2>/dev/null | head -50 | tee "$REPORT_DIR/lsof_output.txt" || echo "  (lsof 失败或无权限)"
    echo "  lsof 已保存到 $REPORT_DIR/lsof_output.txt"
    echo ""
fi

# 4. 网络连接（如果有后端存储）
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-4] daemon 网络连接 ---"
    ss -tnp 2>/dev/null | grep "pid=$DAEMON_PID" | head -20 || echo "  (无网络连接或不可用)"
    echo ""
fi

# 5. 客户端操作全追踪
if [ -n "$MOUNT_POINT" ]; then
    echo "--- [L2-5] 客户端操作追踪 ---"
    timeout 5 strace -e trace=all ls -la "$MOUNT_POINT" 2>&1 | head -30 \
        | tee "$REPORT_DIR/client_trace.txt"
    echo "  客户端 strace 已保存到 $REPORT_DIR/client_trace.txt"
    echo ""
fi

# 6. 连接详情快照
echo "--- [L2-6] 连接详情快照 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    echo "  连接 $conn_id:" | tee -a "$REPORT_DIR/connections.txt"
    for attr in waiting max_background max_read abort congested_threshold_ms; do
        val=$(cat "$conn/$attr" 2>/dev/null || echo "N/A")
        echo "    $attr: $val" | tee -a "$REPORT_DIR/connections.txt"
    done
    echo "" >> "$REPORT_DIR/connections.txt"
done
echo "  连接快照已保存到 $REPORT_DIR/connections.txt"
echo ""

# 7. 全部 dmesg
echo "--- [L2-7] 最近 dmesg ---"
dmesg | tail -50 2>/dev/null | tee "$REPORT_DIR/dmesg.txt" || echo "  (dmesg 不可用)"
echo "  dmesg 已保存到 $REPORT_DIR/dmesg.txt"
echo ""

# 8. 配置快照差异（如果存在历史快照）
echo "--- [L2-8] 当前 FUSE 配置快照 ---"
{
    echo "=== mount -t fuse ==="
    mount -t fuse 2>/dev/null
    echo "=== /proc/mounts fuse ==="
    grep fuse /proc/mounts 2>/dev/null
    echo "=== FUSE 模块参数 ==="
    cat /sys/module/fuse/parameters/* 2>/dev/null
    echo "=== /dev/fuse ==="
    ls -la /dev/fuse 2>/dev/null
} | tee "$REPORT_DIR/config_snapshot.txt"
echo "  配置快照已保存到 $REPORT_DIR/config_snapshot.txt"
echo ""

# ---- 交叉分析 ----
echo "============================================"
echo " 交叉分析"
echo "============================================"

# 收集所有异常指标
anomalies=""

waiting_vals=""
for conn in /sys/fs/fuse/connections/*/; do
    w=$(cat "$conn/waiting" 2>/dev/null)
    [ -n "$w" ] && waiting_vals="$waiting_vals $w"
done

max_w=0
for w in $waiting_vals; do
    [ "$w" -gt "$max_w" ] && max_w=$w
done

mr=$(cat /sys/fs/fuse/connections/*/max_read 2>/dev/null | head -1)
wb=$(cat /sys/module/fuse/parameters/use_writeback_cache 2>/dev/null)

[ "$max_w" -gt 10 ] && anomalies="$anomalies [队列阻塞 waiting=$max_w]"
[ -n "$mr" ] && [ "$mr" -le 65536 ] 2>/dev/null && anomalies="$anomalies [max_read=$mr 过小]"
[ "$wb" = "1" ] && anomalies="$anomalies [writeback_cache 启用]"

if [ -n "$DAEMON_PID" ]; then
    d_state=$(ps -o stat= -p "$DAEMON_PID" 2>/dev/null)
    [ "$d_state" = "D" ] && anomalies="$anomalies [daemon D 状态]"
fi

echo "  检测到异常:"
if [ -n "$anomalies" ]; then
    echo "    $anomalies"
else
    echo "    (无明显异常指标)"
fi
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

echo "  异常指标数: $(echo $anomalies | wc -w)"
echo ""

if [ $(echo $anomalies | wc -w) -ge 3 ]; then
    echo "结论: 多种故障共存（多重配置叠加/多故障串联）。"
    echo "根因: 建议逐一修复并按优先级排序:"
    echo "  1. 队列阻塞: 增大线程池或后端 I/O 优化"
    echo "  2. max_read 优化: 设置为 1MB 以上"
    echo "  3. writeback cache: 确认 daemon 正确实现回调"
    echo "详细分析请检查各子报告。"
elif [ $(echo $anomalies | wc -w) -ge 1 ]; then
    echo "结论: 检测到少数异常指标，推荐执行对应分支脚本深入分析:"
    echo "  $anomalies"
    echo "根因: 单一故障模式为主，建议使用对应分支脚本精确定位。"
else
    echo "结论: 当前未检测到明显 FUSE 异常。"
    echo "根因: 可能为间歇性问题或非 FUSE 层故障，建议扩大分析范围。"
fi

echo ""
echo "所有诊断数据已保存到: $REPORT_DIR"
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
