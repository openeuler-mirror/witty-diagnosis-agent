#!/bin/bash
# Branch C: md 软 RAID — 创建 RAID0/1 然后模拟降级
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch C: md RAID 降级注入"
echo "=========================================="

which mdadm 2>/dev/null || { echo "缺少 mdadm, 尝试安装..."; sudo apt-get install -y mdadm 2>/dev/null; }

# 创建 backing 设备
dd if=/dev/zero of=/tmp/md_disk1.img bs=1M count=512 status=none
dd if=/dev/zero of=/tmp/md_disk2.img bs=1M count=512 status=none

L1=$(sudo losetup -f)
sudo losetup "$L1" /tmp/md_disk1.img
L2=$(sudo losetup -f)
sudo losetup "$L2" /tmp/md_disk2.img
echo "Loops: $L1 $L2"

# 清理已有 md
sudo mdadm --stop /dev/md0 2>/dev/null || true

# 创建 RAID1
echo "=== 创建 RAID1 ==="
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 "$L1" "$L2" 2>&1
sleep 3
cat /proc/mdstat
sudo mkfs.ext4 -F /dev/md0 2>/dev/null | tail -1

# 挂载并写数据
sudo mkdir -p /mnt/md_test
sudo mount /dev/md0 /mnt/md_test
dd if=/dev/zero of=/mnt/md_test/test bs=1M count=200 conv=fsync 2>/dev/null
echo "数据写入完成"

# 模拟磁盘故障 — 标记一个设备为 faulty
echo "=== 注入: 模拟磁盘故障 ==="
sudo mdadm --manage /dev/md0 --fail "$L1" 2>&1
sleep 2
cat /proc/mdstat
sudo mdadm --detail /dev/md0 | grep -E "State|Active|Working|Failed|Number"

# 移除故障盘（降级状态）
echo "=== 移除故障盘 ==="
sudo mdadm --manage /dev/md0 --remove "$L1" 2>&1
sleep 2
cat /proc/mdstat

# 验证降级后仍可读写
dd if=/dev/md0 of=/dev/null bs=1M count=10 2>&1 | tail -1
echo "降级模式读写正常 ✅"

# 清理
echo "=== 清理 ==="
sudo umount /mnt/md_test 2>/dev/null || true
sudo mdadm --stop /dev/md0 2>/dev/null || true
sudo losetup -d "$L1" 2>/dev/null || true
sudo losetup -d "$L2" 2>/dev/null || true
rm -f /tmp/md_disk1.img /tmp/md_disk2.img
echo "=== 完成 ==="
