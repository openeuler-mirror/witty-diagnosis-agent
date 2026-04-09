#!/bin/bash
# Description: V3 Kernel Self-Guard & Resource Saturation (Time-Enhanced)
# 目标：通过对齐资源压力峰值时刻与系统崩溃时刻，判定是否触发了内核自保策略。

show_help() {
    echo "Usage: $0"
    echo "提取 OOM、Softlockup 的精确时刻，并对比重启前的负载趋势。"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then show_help; exit 0; fi

echo "=== [DEEP_ANALYSIS: V3_KERNEL_GUARD_TIME] ==="

# --- [V0] 系统时间基准 ---
echo "[TIME_CONTEXT]"
echo "System_Current_Time: $(date "+%Y-%m-%d %H:%M:%S")"
echo "System_Boot_Timestamp: $(uptime -s)"
echo "--------------------------------------"

# --- [STEP 1] OOM 发生的确切时刻 ---
echo "[STEP 1] 正在检索重启前的 OOM (Out of Memory) 时间点..."
# 使用 --boot=-1 确保回溯到上一次启动的最后瞬间
OOM_LOG=$(journalctl --boot=-1 -k --no-pager 2>/dev/null | grep -iE "Out of memory|Killed process")
if [ -n "$OOM_LOG" ]; then
    echo "$OOM_LOG" | tail -n 5 | sed 's/^/  [OOM_EVENT] /'
    # 提取最后一次 OOM 的时间戳用于对比
    LAST_OOM_TIME=$(echo "$OOM_LOG" | tail -n 1 | awk '{print $1,$2,$3}')
    echo "  >> 识别到最后一次 OOM 发生时间: $LAST_OOM_TIME"
else
    echo "  [INFO] 未发现重启前的 OOM 杀进程记录。"
fi

# --- [STEP 2] 资源压力峰值对比 (SAR) ---
echo -e "\n[STEP 2] 正在提取事故发生前的负载快照 (SAR)..."
SA_FILE="/var/log/sa/sa$(date +%d)"
if [ -f "$SA_FILE" ]; then
    # 提取最后 10 条记录，并显示 SAR 的时间戳
    echo "  [SAR_SNAPSHOT] 重启前的历史负载趋势:"
    sar -q -f "$SA_FILE" | tail -n 10 | sed 's/^/    / '
else
    echo "  [WARN] 未发现 SAR 历史数据，无法精确回溯分钟级压力。"
fi

# --- [STEP 3] 策略触发阈值 ---
echo -e "\n[STEP 3] 内核自保策略触发点 (Thresholds)..."
# 这里的配置决定了内核在什么时间点会“忍无可忍”选择重启
sysctl -a 2>/dev/null | grep -E "panic_on_oom|softlockup_panic|kernel.panic|hung_task_panic" | sed 's/^/  [POLICY] /'

echo -e "\n=== [DIAGNOSIS_LOGIC] ==="
echo "分析方法：对比 [OOM_EVENT] 的时间戳是否在 [System_Boot_Timestamp] 之前的 30 秒内。"
echo "如果是，则重启原因是：内存耗尽触发了 panic_on_oom 强制复位。"