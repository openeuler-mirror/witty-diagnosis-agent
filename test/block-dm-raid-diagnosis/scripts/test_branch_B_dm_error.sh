#!/bin/bash
# Branch B: DM 映射栈 — 创建 dm-error 设备模拟映射故障
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch B: DM error 注入"
echo "=========================================="

which dmsetup losetup 2>/dev/null || { echo "缺少 dmsetup/losetup"; exit 1; }

# 清理残留
sudo dmsetup remove dm-test 2>/dev/null || true

# 创建 backing file + loop
dd if=/dev/zero of=/tmp/dm_test.img bs=1M count=512 status=none
LOOP=$(sudo losetup -f)
sudo losetup "$LOOP" /tmp/dm_test.img
echo "Loop: $LOOP"

# 先创建正常 linear 设备
SZ=$(sudo blockdev --getsz "$LOOP")
HALF=$((SZ / 2))
sudo dmsetup create dm-test --table "0 $HALF linear $LOOP 0"
echo "=== 正常 DM 设备创建 ==="
sudo dmsetup table dm-test
sudo mkfs.ext4 -F /dev/mapper/dm-test 2>/dev/null | tail -1

# 挂载后写数据
sudo mkdir -p /mnt/dm_test
sudo mount /dev/mapper/dm-test /mnt/dm_test
dd if=/dev/zero of=/mnt/dm_test/test bs=1M count=100 conv=fsync 2>/dev/null
echo "写入正常"

# 替换为 error 目标模拟映射故障
echo "=== 注入: 将 dm-test 替换为 error 目标 ==="
sudo dmsetup load dm-test --table "0 $HALF error"
sudo dmsetup resume dm-test
echo "DM 设备已切换为 error 目标"

# 测试读写应报 IO 错误
echo "=== 验证: 读写 error 设备 ==="
dd if=/dev/mapper/dm-test of=/dev/null bs=4k count=10 2>&1 | tail -3 || echo "读错误 ✅"
dd if=/dev/zero of=/mnt/dm_test/test2 bs=4k count=10 2>&1 | tail -3 || echo "写错误 ✅"

# 收集证据
dmesg | grep -i "I/O error\|buffer I/O" | tail -5

# 恢复
echo "=== 清理 ==="
sudo umount /mnt/dm_test 2>/dev/null || true
sudo dmsetup remove dm-test 2>/dev/null || true
sudo losetup -d "$LOOP" 2>/dev/null || true
rm -f /tmp/dm_test.img
echo "=== 完成 ==="
