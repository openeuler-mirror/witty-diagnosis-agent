#!/bin/bash
# Description: V2 Human Action Traceability (Time-Sensitive Edition)
# 目标：提取带时间戳的人为操作证据，用于与系统启动时间和崩溃时间对齐。

show_help() {
    echo "Usage: $0"
    echo "溯源重启指令的操作者、精确时间戳及 TTY 来源。"
}

if [[ "$1" == "--help" || "$1" == "-h" ]]; then show_help; exit 0; fi

echo "=== [DEEP_ANALYSIS: V2_HUMAN_TRACE] ==="

# --- [V0] 系统时间基准 ---
# 记录系统本次启动的时间，作为判断“人为操作”是否发生在重启前的参照
echo "[TIME_CONTEXT]"
echo "System_Current_Time: $(date "+%Y-%m-%d %H:%M:%S")"
echo "System_Boot_Timestamp: $(uptime -s)"
echo "--------------------------------------"

# --- [STEP 1] 审计日志时间线 ---
echo "[STEP 1] 正在检索系统审计 (Auditd) 历史记录..."
if command -v ausearch &> /dev/null; then
    # 提取最近 3 次关机/启动事件的精确纳秒级时间
    ausearch -m system_shutdown,system_boot -i 2>/dev/null | grep -E "type=SYSTEM_SHUTDOWN|type=SYSTEM_BOOT|msg=audit" | tail -n 10 | sed 's/^/  [AUDIT] /'
else
    echo "  [WARN] auditd 未运行，无法获取指令触发的精确时刻。"
fi

# --- [STEP 2] 历史命令的物理时间 ---
echo -e "\n[STEP 2] 正在扫描 root 历史命令及其文件修改时间..."
if [ -f /root/.bash_history ]; then
    # 核心逻辑：获取 .bash_history 文件的最后修改时间
    # 如果你在重启前敲了 reboot，文件的修改时间通常会停留在重启前的那一刻
    HIST_MTIME=$(stat -c %y /root/.bash_history 2>/dev/null | cut -d. -f1)
    echo "  [FILE_MARK] .bash_history 最后写入时刻: $HIST_MTIME"
    
    # 尝试开启 bash 历史的时间显示（如果当前环境支持）
    export HISTTIMEFORMAT="%F %T "
    echo "  [HISTORY_SNAPSHOT] 最近的敏感指令:"
    grep -E "reboot|shutdown|init 6|systemctl" /root/.bash_history | tail -n 5 | sed 's/^/    > /'
else
    echo "  [WARN] 未发现历史命令记录文件。"
fi

# --- [STEP 3] 登录会话与关机标记 ---
echo -e "\n[STEP 3] 正在回溯 last 日志中的会话断层..."
# last -x 可以显示 shutdown 和 reboot 的虚拟条目，帮助对齐时间
last -x -i -F | head -n 6 | sed 's/^/  [LAST_X] /'

echo -e "\n=== [DIAGNOSIS_ADVICE] ==="
echo "提示：请对比 [FILE_MARK] 或 [AUDIT] 的时间与 [System_Boot_Timestamp]。"
echo "如果人为操作时刻早于启动时刻不足 2 分钟，则高度怀疑为【人为触发重启】。"