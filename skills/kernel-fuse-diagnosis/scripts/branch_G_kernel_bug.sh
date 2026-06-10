#!/bin/bash
# branch_G_kernel_bug.sh — FUSE 内核模块 Bug 诊断
# 场景: 内核 Panic/Oops/soft lockup 与 FUSE 相关
# 对应 SKILL.md Branch G
#
# Usage: bash branch_G_kernel_bug.sh

echo "============================================"
echo " Branch G: FUSE 内核模块 Bug 诊断"
echo "============================================"
echo ""

# ---- L2: 类型层诊断 ----

# 1. 内核版本
echo "--- [L2-1] 内核版本 ---"
uname -a
echo ""

# 2. FUSE 模块版本
echo "--- [L2-2] FUSE 模块信息 ---"
modinfo fuse 2>/dev/null | grep -E "^(version|srcversion|description)" || echo "  (modinfo 不可用)"
cat /sys/module/fuse/version 2>/dev/null || echo "  (模块版本文件不可用)"
cat /sys/module/fuse/srcversion 2>/dev/null || echo "  (srcversion 不可用)"
echo ""

# 3. dmesg 内核异常
echo "--- [L2-3] 内核 FUSE 异常 ---"
dmesg | grep -iE "fuse|libfuse" | tail -30 2>/dev/null || echo "  (dmesg 不可用)"
echo ""

# 4. kernel panic / Oops / BUG
echo "--- [L2-4] 内核崩溃/BUG 检查 ---"
dmesg | grep -iE "kernel panic|Oops|BUG|soft lockup|hard lockup" | tail -20 2>/dev/null || echo "  (无内核异常记录)"
echo ""

# 5. FUSE 相关 BUG
echo "--- [L2-5] FUSE 内核 BUG 消息 ---"
dmesg | grep -iE "kernel BUG at.*fuse" 2>/dev/null || echo "  (无 FUSE 内核 BUG)"
dmesg | grep -iE "Call Trace" | head -5 2>/dev/null
echo ""

# 6. 所有 FUSE 挂载
echo "--- [L2-6] 当前所有 FUSE 挂载 ---"
grep fuse /proc/self/mounts 2>/dev/null || echo "  (无 FUSE 挂载)"
echo ""

# 7. 连接 abort 状态
echo "--- [L2-7] FUSE 连接 abort 状态 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    abort_val=$(cat "$conn/abort" 2>/dev/null || echo "N/A")
    echo "  连接 $conn_id: abort=$abort_val"
done
echo ""

# 8. crash dump 检查
echo "--- [L2-8] Crash Dump 检查 ---"
if [ -d /var/crash ]; then
    ls -lh /var/crash/ 2>/dev/null || echo "  (/var/crash 为空)"
    ls -lh /var/crash/vmcore* 2>/dev/null || echo "  (无 vmcore)"
else
    echo "  (/var/crash 不存在)"
fi
kdump_status=$(systemctl is-active kdump 2>/dev/null || echo "unknown")
echo "  kdump 状态: $kdump_status"
echo ""

# 9. 系统日志中的 FUSE 消息
echo "--- [L2-9] 系统日志 FUSE 消息 ---"
for logfile in /var/log/messages /var/log/syslog /var/log/kern.log; do
    if [ -f "$logfile" ]; then
        grep -i "fuse" "$logfile" 2>/dev/null | tail -5 && break
    fi
done || echo "  (无可读系统日志)"
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

kernel_ver=$(uname -r)
fuse_bug=$(dmesg 2>/dev/null | grep -cE "kernel BUG at.*fuse")
fuse_oops=$(dmesg 2>/dev/null | grep -cE "Oops.*fuse")
fuse_slock=$(dmesg 2>/dev/null | grep -cE "soft lockup.*fuse")

echo "  内核版本: $kernel_ver"
echo "  FUSE BUG 次数: $fuse_bug"
echo "  FUSE Oops 次数: $fuse_oops"
echo "  FUSE soft lockup 次数: $fuse_slock"
echo ""

# 已知 Bug 版本匹配
known_bug=""
case "$kernel_ver" in
    5.1[0-5]*)  known_bug="5.10-5.15: 并发挂载竞争 (已修复 5.16)" ;;
    4.1[89]*)   known_bug="4.18-5.0: memory cgroup OOM (已修复 5.1)" ;;
    4.[0-9]*)   known_bug="4.x: 检查具体版本" ;;
    3.1[5-8]*)  known_bug="3.15-3.18: 并发写死锁 (已修复 3.19)" ;;
    3.[0-9]*)   known_bug="3.x: 建议升级内核" ;;
esac

if [ -n "$known_bug" ]; then
    echo "  已知问题: $known_bug"
fi

if [ "$fuse_bug" -gt 0 ] || [ "$fuse_oops" -gt 0 ] || [ "$fuse_slock" -gt 0 ]; then
    echo ""
    echo "结论: 检测到 FUSE 内核级异常。"
    if [ "$fuse_bug" -gt 0 ]; then
        echo "  - kernel BUG in FUSE: 需检查具体 BUG 地址和内核源码"
    fi
    if [ "$fuse_oops" -gt 0 ]; then
        echo "  - Oops in FUSE: 可能 FUSE 模块或驱动 Bug"
    fi
    if [ "$fuse_slock" -gt 0 ]; then
        echo "  - soft lockup in FUSE: FUSE 路径导致 CPU 软死锁"
    fi
    if [ -n "$known_bug" ]; then
        echo "根因: 当前内核版本 ($kernel_ver) 存在已知 FUSE Bug: $known_bug"
        echo "建议: 升级内核到已修复版本"
    else
        echo "根因: 可能为 FUSE 内核模块缺陷，需分析具体 CR2 地址和调用栈。"
        echo "建议: 收集 vmcore 或 dmesg 详细信息，向内核社区报告。"
    fi
else
    echo "结论: 当前未检测到 FUSE 内核级异常。"
    echo "根因: 非 FUSE 内核 Bug，建议排查其他故障类型。"
    if [ -n "$known_bug" ]; then
        echo "提醒: 当前内核版本 ($kernel_ver) 有已知 FUSE Bug，建议升级预防。"
    fi
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
