#!/bin/bash
# Branch D: LVM — 创建 thin pool 并模拟 thin pool 100%
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch D: LVM thin pool 满"
echo "=========================================="

which lvm lvcreate vgcreate pvcreate 2>/dev/null || { echo "缺少 LVM 工具"; exit 1; }

# 创建 backing 设备
dd if=/dev/zero of=/tmp/lvm_disk.img bs=1M count=1024 status=none
LOOP=$(sudo losetup -f)
sudo losetup "$LOOP" /tmp/lvm_disk.img
echo "Loop: $LOOP"

# 清理已有
sudo vgremove -f bdm-vg 2>/dev/null || true
sudo pvremove -f "$LOOP" 2>/dev/null || true

# 创建 PV + VG
echo "=== 创建 PV/VG ==="
sudo pvcreate "$LOOP"
sudo vgcreate bdm-vg "$LOOP"

# 创建 thin pool (data=800M, metadata=64M)
echo "=== 创建 thin pool ==="
sudo lvcreate -L 64M -T bdm-vg/bdm-pool --poolmetadatasize 64M -n bdm-data

# 创建 thin 卷 (超额分配: 1.5G > data 800M)
echo "=== 创建超额 thin 卷 ==="
sudo lvcreate -V 1500M -T bdm-vg/bdm-pool -n bdm-vol

# 格式化 + 挂载
sudo mkfs.ext4 -F /dev/bdm-vg/bdm-vol 2>/dev/null | tail -1
sudo mkdir -p /mnt/bdm_lvm
sudo mount /dev/bdm-vg/bdm-vol /mnt/bdm_lvm

# 写数据直到 thin pool 满
echo "=== 写入数据触发 thin pool 满 ==="
dd if=/dev/zero of=/mnt/bdm_lvm/fill bs=1M count=1200 conv=fsync 2>&1 | tail -3 || echo "thin pool 满 ✅"

# 收集证据
echo "=== LVM 状态 ==="
sudo lvs -a bdm-vg
sudo lvdisplay bdm-vg/bdm-pool | grep -i "metadata\|data\|percent\|health"
dmesg | grep -i "dm-thin\|thin pool\|out of data space" | tail -5

# 清理
echo "=== 清理 ==="
sudo umount /mnt/bdm_lvm 2>/dev/null || true
sudo lvremove -f bdm-vg/bdm-vol 2>/dev/null || true
sudo lvremove -f bdm-vg/bdm-data 2>/dev/null || true
sudo vgremove -f bdm-vg 2>/dev/null || true
sudo pvremove -f "$LOOP" 2>/dev/null || true
sudo losetup -d "$LOOP" 2>/dev/null || true
rm -f /tmp/lvm_disk.img
echo "=== 完成 ==="
