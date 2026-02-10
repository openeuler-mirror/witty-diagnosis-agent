#!/bin/bash
set -u

# 脚本功能：采集OOM相关系统参数和日志信息，用于诊断OOM问题。
# 参数说明：
#   $1: 要检查的进程名（可选，用于过滤进程列表）
#   $2: 要检查的进程PID（可选，用于查看特定进程的oom_score_adj）
# 使用示例：
#   ./collect_oom_diagnostics.sh test
#   ./collect_oom_diagnostics.sh test 2939
#   ./collect_oom_diagnostics.sh

PROCESS_NAME="${1:-}"
PID_TO_CHECK="${2:-}"

# 步骤1：检查OOM相关内核参数
echo "=== 步骤1：检查OOM相关内核参数 ==="
if command -v cat > /dev/null 2>&1; then
    if [ -f "/proc/sys/vm/panic_on_oom" ]; then
        cat /proc/sys/vm/panic_on_oom || echo "警告: 读取panic_on_oom失败"
    else
        echo "警告: 文件/proc/sys/vm/panic_on_oom不存在，跳过"
    fi
    if [ -f "/proc/sys/vm/oom_kill_allocating_task" ]; then
        cat /proc/sys/vm/oom_kill_allocating_task || echo "警告: 读取oom_kill_allocating_task失败"
    else
        echo "警告: 文件/proc/sys/vm/oom_kill_allocating_task不存在，跳过"
    fi
    if [ -f "/proc/sys/vm/oom_dump_tasks" ]; then
        cat /proc/sys/vm/oom_dump_tasks || echo "警告: 读取oom_dump_tasks失败"
    else
        echo "警告: 文件/proc/sys/vm/oom_dump_tasks不存在，跳过"
    fi
else
    echo "警告: 命令cat未找到，跳过步骤1"
fi

# 步骤2：使用sysctl检查OOM相关参数
echo -e "\n=== 步骤2：使用sysctl检查OOM相关参数 ==="
if command -v sysctl > /dev/null 2>&1; then
    sysctl -a | grep panic_on_oom || echo "警告: 使用sysctl grep panic_on_oom失败"
    sysctl -a | grep oom_kill_allocating_task || echo "警告: 使用sysctl grep oom_kill_allocating_task失败"
    sysctl -a | grep oom_dump_tasks || echo "警告: 使用sysctl grep oom_dump_tasks失败"
else
    echo "警告: 命令sysctl未找到，跳过步骤2"
fi

# 步骤3：检查指定进程（如果提供了进程名）
echo -e "\n=== 步骤3：检查进程信息 ==="
if [ -n "$PROCESS_NAME" ]; then
    if command -v ps > /dev/null 2>&1 && command -v grep > /dev/null 2>&1; then
        ps -ef | grep "$PROCESS_NAME" || echo "警告: 查找进程 $PROCESS_NAME 失败"
    else
        echo "警告: 命令ps或grep未找到，跳过进程查找"
    fi
else
    echo "信息: 未提供进程名，跳过进程查找"
fi

# 步骤4：检查指定进程的oom_score_adj（如果提供了PID）
echo -e "\n=== 步骤4：检查指定进程的oom_score_adj ==="
if [ -n "$PID_TO_CHECK" ]; then
    if command -v cat > /dev/null 2>&1; then
        OOM_SCORE_ADJ_FILE="/proc/$PID_TO_CHECK/oom_score_adj"
        if [ -f "$OOM_SCORE_ADJ_FILE" ]; then
            cat "$OOM_SCORE_ADJ_FILE" || echo "警告: 读取 $OOM_SCORE_ADJ_FILE 失败"
        else
            echo "警告: 文件 $OOM_SCORE_ADJ_FILE 不存在，跳过"
        fi
    else
        echo "警告: 命令cat未找到，跳过步骤4"
    fi
else
    echo "信息: 未提供进程PID，跳过检查oom_score_adj"
fi

# 步骤5：检查系统日志中的OOM信息
echo -e "\n=== 步骤5：检查系统日志中的OOM信息 ==="
if [ -f "/var/log/messages" ]; then
    if command -v grep > /dev/null 2>&1; then
        echo "信息: 检查/var/log/messages中与OOM相关的日志"
        grep -i "oom" /var/log/messages || echo "警告: 在/var/log/messages中未找到OOM相关日志"
    else
        echo "警告: 命令grep未找到，跳过日志检查"
    fi
else
    echo "警告: 文件/var/log/messages不存在，跳过日志检查"
fi

echo -e "\n=== 数据采集完成 ==="
