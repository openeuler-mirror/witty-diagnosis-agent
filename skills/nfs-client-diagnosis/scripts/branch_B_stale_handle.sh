#!/bin/bash
# ============================================================
# 脚本：branch_B_stale_handle.sh
# 用途：Stale File Handle 诊断
# 使用：bash branch_B_stale_handle.sh [mount_point] [file_path]
# 参数:
#   $1  受影响的 NFS 挂载点（可选）
#   $2  出现 stale 的文件路径（可选）
# ============================================================

set -euo pipefail

TARGET_MOUNT="${1:-}"
TARGET_FILE="${2:-}"

echo "================================================================"
echo " 分支B: Stale File Handle 诊断"
echo " 挂载点: ${TARGET_MOUNT:-未指定}"
echo " 文件路径: ${TARGET_FILE:-未指定}"
echo "================================================================"

echo ""
echo "=== B1: NFS 客户端 ESTALE 计数统计 ==="
echo "--- nfsstat -c 错误计数 ---"
nfsstat -c 2>/dev/null | grep -iE "stale|ESTALE|error|fault" || echo "nfsstat 不可用或无错误"
echo ""

echo "--- nfsstat -4 -c (NFSv4 错误) ---"
nfsstat -4 -c 2>/dev/null | grep -iE "stale|expired|bad|error" || echo "nfsstat -4 不可用或无 NFSv4 错误"
echo ""

echo "--- /proc/self/mountstats 中的 stale 错误 ---"
grep -i "stale\|ESTALE" /proc/self/mountstats 2>/dev/null || echo "mountstats 中无 stale 记录"
echo ""

echo "=== B2: 内核日志 ESTALE 记录 ==="
dmesg -T 2>/dev/null | grep -iE "stale|ESTALE|NFS:.*error" | tail -30 || echo "无相关内核日志"
echo ""

echo "=== B3: 文件状态确认 ==="
if [ -n "$TARGET_FILE" ]; then
    echo "--- stat ${TARGET_FILE} ---"
    stat "$TARGET_FILE" 2>&1 || echo "⚠️  stat 失败（文件不可访问）"
    echo ""
    echo "--- ls -la 目录 ---"
    dir=$(dirname "$TARGET_FILE")
    ls -la "$dir" 2>&1 | head -20
else
    echo "未指定具体文件路径，跳过文件级检查。"
    if [ -n "$TARGET_MOUNT" ] && mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
        echo "--- ${TARGET_MOUNT} 目录内容 ---"
        ls -la "$TARGET_MOUNT" 2>&1 | head -20
    fi
fi
echo ""

echo "=== B4: NFSv4 clientid 检查 ==="
if [ -f "/proc/net/rpc/nfs4.0/clientid" ]; then
    echo "clientid:"
    cat /proc/net/rpc/nfs4.0/clientid
else
    echo "⚠️  /proc/net/rpc/nfs4.0/clientid 不存在"
fi
echo ""

echo "=== B5: NFS 挂载点 export 同步状态 ==="
echo "--- 当前挂载参数 ---"
if [ -n "$TARGET_MOUNT" ]; then
    mount | grep "$TARGET_MOUNT" 2>/dev/null || echo "挂载点 $TARGET_MOUNT 未挂载"
fi
echo ""

echo "--- showmount -e (export 列表) ---"
nfs_servers=$(mount 2>/dev/null | grep nfs | awk '{print $1}' | sed 's/:[^:]*$//' | sort -u | head -5)
for svr in $nfs_servers; do
    echo "Server: $svr"
    timeout 5 showmount -e "$svr" 2>&1 | head -10 || echo "  showmount 失败"
    echo ""
done

echo "=== B6: lsof 检查挂载点上打开的文件句柄 ==="
if [ -n "$TARGET_MOUNT" ] && mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
    lsof +D "$TARGET_MOUNT" 2>/dev/null | head -30 || echo "lsof 不可用或无打开文件"
    echo ""
    echo "--- fuser 检查 ---"
    fuser -v "$TARGET_MOUNT" 2>/dev/null || echo "fuser 不可用或无访问进程"
else
    echo "未指定有效挂载点，跳过 lsof 检查。"
fi

echo ""
echo "================================================================"
echo " 分支B 诊断结论模板"
echo "================================================================"
echo ""
echo "ESTALE 计数: [有增长/无增长]"
echo "  nfsstat: [具体计数]"
echo "  mountstats: [具体错误]"
echo "内核日志: [有ESTALE记录/无]"
echo "文件状态: [存在/不存在/不可访问]"
echo "clientid: [有效/过期/不存在]"
echo ""
echo "根因分类:"
echo "  □ 服务端文件被删除后客户端仍持有 fd"
echo "  □ export 路径变化 / NFS 服务重启"
echo "  □ NFSv4 clientid 冲突/过期"
echo "  □ 文件句柄缓存过期"
echo "================================================================"
