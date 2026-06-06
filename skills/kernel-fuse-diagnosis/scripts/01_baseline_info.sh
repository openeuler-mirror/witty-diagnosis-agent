#!/bin/bash
# 01_baseline_info.sh — FUSE 环境基线信息采集
# 输出：系统 FUSE 环境、挂载点、连接状态、daemon 进程信息
# 供 SKILL.md 第三节 Step 1 使用
#
# Usage: bash 01_baseline_info.sh [mount_point] [daemon_name]

MOUNT_POINT="${1:-}"
DAEMON_NAME="${2:-}"

echo "============================================"
echo " FUSE 环境基线信息采集"
echo "============================================"
echo ""

# ---- V1: FUSE 模块状态 ----
echo "--- [V1] FUSE 内核模块 ---"
if lsmod | grep -q "^fuse"; then
    echo "FUSE 模块状态: 已加载"
    modinfo fuse 2>/dev/null | grep -E "^(version|description|srcversion|parm)" || echo "  (modinfo 不可用)"
else
    echo "FUSE 模块状态: 未加载"
fi
echo ""

# 模块参数
for param in max_read max_write use_writeback_cache; do
    val=$(cat /sys/module/fuse/parameters/$param 2>/dev/null)
    echo "  fuse.$param = ${val:-N/A}"
done
echo ""

# ---- V2: FUSE 挂载点 ----
echo "--- [V2] FUSE 挂载点 ---"
fuse_mounts=$(mount -t fuse 2>/dev/null)
if [ -n "$fuse_mounts" ]; then
    echo "$fuse_mounts"
else
    echo "  (无 FUSE 挂载点)"
fi
echo ""

# 检查 /proc/mounts
proc_fuse=$(grep fuse /proc/mounts 2>/dev/null)
if [ -n "$proc_fuse" ]; then
    echo "  /proc/mounts FUSE 条目数: $(echo "$proc_fuse" | wc -l)"
fi
echo ""

# ---- V3: FUSE 连接状态 (sysfs) ----
echo "--- [V3] FUSE 内核连接 (sysfs) ---"
conns=$(ls /sys/fs/fuse/connections/ 2>/dev/null)
if [ -n "$conns" ]; then
    for conn in $conns; do
        conn_path="/sys/fs/fuse/connections/$conn"
        echo "  连接 ID: $conn"
        echo "    waiting:            $(cat $conn_path/waiting 2>/dev/null || echo N/A)"
        echo "    max_background:     $(cat $conn_path/max_background 2>/dev/null || echo N/A)"
        echo "    max_read:           $(cat $conn_path/max_read 2>/dev/null || echo N/A)"
        echo "    abort:              $(cat $conn_path/abort 2>/dev/null || echo N/A)"
        echo "    congested_threshold_ms: $(cat $conn_path/congested_threshold_ms 2>/dev/null || echo N/A)"
        echo ""
    done
else
    echo "  (无活跃 FUSE 连接)"
fi

# ---- V4: FUSE daemon 进程 ----
echo "--- [V4] FUSE Daemon 进程 ---"
if [ -n "$DAEMON_NAME" ]; then
    pgrep -f "$DAEMON_NAME" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  Daemon 进程状态: 运行中 (目标: $DAEMON_NAME)"
        ps aux | grep -E "[${DAEMON_NAME:0:1}]${DAEMON_NAME:1}" | head -5
    else
        echo "  Daemon 进程: 未找到 ($DAEMON_NAME)"
    fi
else
    echo "  (未指定 daemon 名称，列出所有可能 FUSE 进程)"
    ps aux | grep -E "[f]use" || echo "  (无)"
fi
echo ""

# ---- V5: 挂载点连通性 ----
if [ -n "$MOUNT_POINT" ]; then
    echo "--- [V5] 挂载点连通性 ($MOUNT_POINT) ---"
    stat "$MOUNT_POINT" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "  stat: 成功"
        ls -la "$MOUNT_POINT" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "  ls -la: 成功"
        else
            echo "  ls -la: 失败 ($?)"
        fi
    else
        echo "  stat: 失败 (挂载点不可达)"
    fi
    echo ""
fi

# ---- V6: /dev/fuse 设备 ----
echo "--- [V6] /dev/fuse 设备 ---"
if [ -c /dev/fuse ]; then
    ls -la /dev/fuse
    getfacl /dev/fuse 2>/dev/null | head -5
else
    echo "  /dev/fuse 设备不存在"
fi
echo ""

# ---- V7: /etc/fuse.conf ----
echo "--- [V7] FUSE 配置 ---"
if [ -f /etc/fuse.conf ]; then
    cat /etc/fuse.conf 2>/dev/null
else
    echo "  /etc/fuse.conf 不存在"
fi
echo ""

# ---- V8: 分支推荐 ----
echo "============================================"
echo " 分支推荐 (基于基线信息)"
echo "============================================"

conn_count=$(ls /sys/fs/fuse/connections/ 2>/dev/null | wc -l)
if [ "$conn_count" -eq 0 ]; then
    echo "  连接数: 0 — 可能无 FUSE 活动或 daemon 已崩溃"
    echo "  → 推荐: branch_A_daemon_crash.sh"
fi

if [ -n "$MOUNT_POINT" ]; then
    stat "$MOUNT_POINT" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "  stat 挂载点失败 — 连接可能已断开"
        echo "  → 推荐: branch_A_daemon_crash.sh"
    fi
fi

for conn in $conns; do
    waiting=$(cat /sys/fs/fuse/connections/$conn/waiting 2>/dev/null)
    if [ -n "$waiting" ] && [ "$waiting" -gt 10 ] 2>/dev/null; then
        echo "  waiting=$waiting (连接 $conn) — 请求队列深度异常"
        echo "  → 推荐: branch_B_req_queue.sh"
    fi
    mr=$(cat /sys/fs/fuse/connections/$conn/max_read 2>/dev/null)
    if [ -n "$mr" ] && [ "$mr" -le 65536 ] 2>/dev/null; then
        echo "  max_read=$mr — 可能过小"
        echo "  → 推荐: branch_C_max_read_write.sh"
    fi
done

use_wb=$(cat /sys/module/fuse/parameters/use_writeback_cache 2>/dev/null)
if [ "$use_wb" = "1" ]; then
    echo "  writeback_cache 已启用 — 如有数据不一致怀疑"
    echo "  → 推荐: branch_D_writeback_cache.sh"
fi

echo ""
echo "采集完成: $(date '+%Y-%m-%d %H:%M:%S')"
