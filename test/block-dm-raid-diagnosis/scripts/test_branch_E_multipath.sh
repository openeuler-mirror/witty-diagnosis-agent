#!/bin/bash
# Branch E: Multipath — WSL 不支持 multipath, 使用 dm-multipath 模拟
# WSL 注入脚本 (模拟路径失效场景)
set -e

echo "=========================================="
echo " Block-dm-raid Branch E: Multipath 模拟"
echo "=========================================="

which dmsetup multipath 2>/dev/null || echo "multipath-tools 可能未安装"

# WSL 中 multipath 设备通常不可用, 使用 dm-linear 模拟多路径
# 创建两个 loop 设备模拟两个路径
dd if=/dev/zero of=/tmp/mp_disk.img bs=1M count=512 status=none
L1=$(sudo losetup -f)
sudo losetup "$L1" /tmp/mp_disk.img

SZ=$(sudo blockdev --getsz "$L1")

# 模拟: 创建两个 linear dm 设备表示两条路径
sudo dmsetup create mp-path1 --table "0 $SZ linear $L1 0"
echo "=== 两条虚拟路径 ==="
sudo dmsetup table mp-path1

# 模拟路径失效: 将一条路径切换为 error
echo "=== 注入: 路径1 失效 (error) ==="
sudo dmsetup load mp-path1 --table "0 $SZ error"
sudo dmsetup resume mp-path1

# 验证错误
echo "=== 验证: 读失效路径 ==="
dd if=/dev/mapper/mp-path1 of=/dev/null bs=4k count=10 2>&1 | tail -3
dmesg | grep -i "I/O error" | tail -3

# 恢复
echo "=== 清理 ==="
sudo dmsetup remove mp-path1 2>/dev/null || true
sudo losetup -d "$L1" 2>/dev/null || true
rm -f /tmp/mp_disk.img
echo "=== 完成 ==="
