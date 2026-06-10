#!/bin/bash
# branch_C_max_read_write.sh — FUSE max_read/max_write 配置不当诊断
# 场景: FUSE 文件系统性能显著低于预期
# 对应 SKILL.md Branch C
#
# Usage: bash branch_C_max_read_write.sh <mount_point> [daemon_pid]

MOUNT_POINT="${1:?错误: 需要挂载点路径作为第一个参数}"
DAEMON_PID="${2:-}"
TEST_FILE="$MOUNT_POINT/.fuse_bench_test"

echo "============================================"
echo " Branch C: max_read/max_write 配置诊断"
echo "============================================"
echo "  挂载点: $MOUNT_POINT"
echo ""

# ---- L2: 类型层诊断 ----

# 1. 当前 max_read/max_write
echo "--- [L2-1] 当前 FUSE 传输参数 ---"
for conn in /sys/fs/fuse/connections/*/; do
    conn_id=$(basename "$conn")
    mr=$(cat "$conn/max_read" 2>/dev/null)
    echo "  连接 $conn_id: max_read=$mr"
done
echo "  内核模块:"
echo "    max_read=$(cat /sys/module/fuse/parameters/max_read 2>/dev/null || echo N/A)"
echo "    max_write=$(cat /sys/module/fuse/parameters/max_write 2>/dev/null || echo N/A)"
echo "    use_writeback_cache=$(cat /sys/module/fuse/parameters/use_writeback_cache 2>/dev/null || echo N/A)"
echo ""

# 2. 挂载参数
echo "--- [L2-2] 挂载参数 ---"
mount | grep "$MOUNT_POINT" 2>/dev/null || echo "  (挂载点不在 mount 输出中)"
grep "$MOUNT_POINT" /proc/mounts 2>/dev/null || echo "  (挂载点不在 /proc/mounts 中)"
echo ""

# 3. 读性能测试
echo "--- [L2-3] 读性能测试 ---"
dd if="$MOUNT_POINT" of=/dev/null bs=1M count=100 2>&1 || echo "  (读测试失败)"
echo ""

# 4. 写性能测试
echo "--- [L2-4] 写性能测试 ---"
dd if=/dev/zero of="$TEST_FILE" bs=1M count=100 2>&1 || echo "  (写测试失败)"
rm -f "$TEST_FILE" 2>/dev/null
echo ""

# 5. strace 对比
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-5] strace 传输大小采样 (5 秒) ---"
    timeout 5 strace -e pread64,pwrite64 -p "$DAEMON_PID" -c 2>&1 || echo "  (strace 失败)"
    echo ""
fi

# 6. 小文件测试对比
echo "--- [L2-6] 小文件读写测试 (4K) ---"
dd if=/dev/zero of="$TEST_FILE" bs=4K count=1000 2>&1
rm -f "$TEST_FILE" 2>/dev/null
echo ""

# 7. 后端 I/O 延迟（如果有底层设备）
echo "--- [L2-7] 后端 I/O 延迟 ---"
# 尝试找到挂载点所在设备
dev=$(df "$MOUNT_POINT" 2>/dev/null | tail -1 | awk '{print $1}')
if [ -n "$dev" ] && [ "$dev" != "fuse" ]; then
    echo "  底层设备: $dev"
    iostat -x 1 3 "$dev" 2>/dev/null | tail -10 || echo "  (iostat 不可用)"
else
    echo "  挂载点为 FUSE 类型，底层设备信息不可直接获取"
fi
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

# 获取 max_read
mr=$(cat /sys/fs/fuse/connections/*/max_read 2>/dev/null | head -1)
kmr=$(cat /sys/module/fuse/parameters/max_read 2>/dev/null)
kmw=$(cat /sys/module/fuse/parameters/max_write 2>/dev/null)

echo "  连接 max_read: ${mr:-N/A}"
echo "  模块 max_read: ${kmr:-N/A}"
echo "  模块 max_write: ${kmw:-N/A}"
echo ""

if [ -n "$mr" ] && [ "$mr" -le 65536 ] 2>/dev/null; then
    echo "结论: max_read=${mr}（<= 64K），远低于推荐值。"
    echo "根因: FUSE 挂载时未指定充足的 max_read，"
    echo "      导致大文件顺序读性能显著退化。"
    echo "建议: 挂载时指定 -o max_read=1048576（1MB）"
elif [ -n "$mr" ] && [ "$mr" -le 262144 ] 2>/dev/null; then
    echo "结论: max_read=${mr}（= 256K），低于大文件读性能推荐值。"
    echo "根因: max_read 可进一步优化以获得更好读性能。"
    echo "建议: 对大文件顺序读场景，推荐 max_read=1048576"
else
    echo "结论: max_read=${mr:-未知}，在正常或较高范围。"
    echo "根因: 当前性能问题非 max_read/max_write 配置导致。"
    echo "      建议检查 daemon 侧处理逻辑或后端存储性能。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
