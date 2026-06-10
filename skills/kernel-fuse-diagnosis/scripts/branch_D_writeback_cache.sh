#!/bin/bash
# branch_D_writeback_cache.sh — FUSE Writeback Cache 一致性问题诊断
# 场景: 写入数据后读取不一致、写入顺序错误
# 对应 SKILL.md Branch D
#
# Usage: bash branch_D_writeback_cache.sh <mount_point> [daemon_pid]

MOUNT_POINT="${1:?错误: 需要挂载点路径作为第一个参数}"
DAEMON_PID="${2:-}"
TEST_FILE="$MOUNT_POINT/.fuse_wb_test"

echo "============================================"
echo " Branch D: Writeback Cache 一致性诊断"
echo "============================================"
echo "  挂载点: $MOUNT_POINT"
echo ""

# ---- L2: 类型层诊断 ----

# 1. writeback_cache 是否启用
echo "--- [L2-1] Writeback Cache 状态 ---"
mount | grep "$MOUNT_POINT" | grep -o "writeback_cache" || echo "  writeback_cache: 未启用（挂载参数中）"
wb=$(cat /sys/module/fuse/parameters/use_writeback_cache 2>/dev/null)
echo "  内核参数 use_writeback_cache: $wb"
echo ""

# 2. 一致性测试: 写入后立即读取
echo "--- [L2-2] 基本一致性测试 ---"
echo "Hello FUSE Writeback $(date)" > "$TEST_FILE" 2>&1
read_back=$(cat "$TEST_FILE" 2>&1)
echo "  写入内容: Hello FUSE Writeback $(date)"
echo "  读取内容: $read_back"
if [ "$read_back" = "Hello FUSE Writeback $(date)" ]; then
    echo "  判定: 一致"
else
    echo "  判定: 不一致！"
fi
echo ""

# 3. 一致性测试: 重复写入对比
echo "--- [L2-3] 重复写入 md5 对比 ---"
dd if=/dev/urandom of="$TEST_FILE" bs=4K count=100 2>/dev/null
md5_1=$(md5sum "$TEST_FILE" 2>/dev/null | awk '{print $1}')
echo "  md5 (写后即时): $md5_1"
sleep 2
md5_2=$(md5sum "$TEST_FILE" 2>/dev/null | awk '{print $1}')
echo "  md5 (2秒后):     $md5_2"
if [ "$md5_1" = "$md5_2" ]; then
    echo "  判定: 数据稳定"
else
    echo "  判定: 数据不稳定！(可能存在 writeback 延迟或一致性缺陷)"
fi
rm -f "$TEST_FILE" 2>/dev/null
echo ""

# 4. 并发写入测试
echo "--- [L2-4] 并发写入一致性测试 ---"
for i in $(seq 1 10); do
    echo "data_$i $(date +%N)" > "$MOUNT_POINT/.concurrent_test_$i" &
done
wait
echo "  已创建 10 个并发写入文件"
mismatch=0
for i in $(seq 1 10); do
    content=$(cat "$MOUNT_POINT/.concurrent_test_$i" 2>/dev/null)
    expected="data_$i"
    if ! echo "$content" | grep -q "$expected"; then
        echo "  Mismatch: .concurrent_test_$i (预期含 $expected)"
        mismatch=$((mismatch+1))
    fi
    rm -f "$MOUNT_POINT/.concurrent_test_$i" 2>/dev/null
done
if [ $mismatch -eq 0 ]; then
    echo "  并发一致性测试: 通过"
else
    echo "  并发一致性测试: $mismatch 个文件不一致！"
fi
echo ""

# 5. strace 写操作跟踪
if [ -n "$DAEMON_PID" ]; then
    echo "--- [L2-5] strace 写操作跟踪 ---"
    timeout 5 strace -e trace=write,pwrite64,fsync -p "$DAEMON_PID" -c 2>&1 || echo "  (strace 失败)"
    echo ""
fi

# 6. 数据变化检测（md5 序列）
echo "--- [L2-6] 写入后多次 md5 变化检测 ---"
dd if=/dev/urandom of="$TEST_FILE" bs=1K count=64 2>/dev/null
for i in $(seq 1 5); do
    md5=$(md5sum "$TEST_FILE" 2>/dev/null | awk '{print $1}')
    echo "  第 ${i} 次: $md5"
    sleep 1
done
rm -f "$TEST_FILE" 2>/dev/null
echo ""

# 7. 缓存无效化检查
echo "--- [L2-7] Page Cache / 内核缓存状态 ---"
vfs_cache=$(cat /proc/meminfo 2>/dev/null | grep -E "(Dirty|Writeback|WritebackTmp)" || echo "  (/proc/meminfo 不可用)")
echo "$vfs_cache"
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

wb_enabled=$(cat /sys/module/fuse/parameters/use_writeback_cache 2>/dev/null)
mount_wb=$(mount | grep "$MOUNT_POINT" | grep -o "writeback_cache")

if [ "$wb_enabled" = "1" ] || [ -n "$mount_wb" ]; then
    echo "结论: writeback_cache 已启用，但可能出现数据一致性问题。"
    echo "根因: FUSE daemon 启用 writeback_cache 模式后，"
    if [ -n "$DAEMON_PID" ]; then
        echo "      需确认 daemon 是否正确实现了 ->write() 和 ->flush() 回调，"
        echo "      以及是否支持 writeback 语义（按序刷入、fsync 正确处理）。"
    else
        echo "      需检查 daemon 是否正确处理 writeback 回调。"
    fi
    echo "建议:"
    echo "  1. 确认 daemon 实现 ->write() 回调"
    echo "  2. 确认 ->flush() 和 ->fsync() 语义正确"
    echo "  3. 确认 page cache 无效化机制（invalidate_inode_pages2）"
    echo "  4. 如果数据一致性难以保证，考虑禁用 writeback_cache"
else
    echo "结论: writeback_cache 未启用，非 writeback 一致性问题。"
    echo "根因: 当前数据问题非 writeback cache 导致，建议排查其他方向。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
