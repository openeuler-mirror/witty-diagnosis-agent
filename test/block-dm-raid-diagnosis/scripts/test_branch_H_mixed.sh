#!/bin/bash
# Branch H: 混合故障 — dm-delay 慢设备 + fio 压力
# WSL 注入脚本
set -e

echo "=========================================="
echo " Block-dm-raid Branch H: 混合故障注入"
echo "=========================================="

which dmsetup losetup fio 2>/dev/null || { echo "缺少工具"; exit 1; }

# 创建慢设备 (组合 dm-delay + 大压力)
sudo modprobe dm-delay 2>/dev/null || true

dd if=/dev/zero of=/tmp/mixed_dev.img bs=1M count=1024 status=none
LOOP=$(sudo losetup -f)
sudo losetup "$LOOP" /tmp/mixed_dev.img
SZ=$(sudo blockdev --getsz "$LOOP")

# 延迟: 读 50ms, 写 100ms
sudo dmsetup create mixed-dev --table "0 $SZ delay $LOOP 0 50 $LOOP 0 100"
echo "=== 慢设备创建: 读50ms 写100ms ==="

sudo mkfs.ext4 -F /dev/mapper/mixed-dev 2>/dev/null | tail -1
sudo mkdir -p /mnt/mixed_test
sudo mount /dev/mapper/mixed-dev /mnt/mixed_test

# 混合压力: 多个进程同时读+写
echo "=== 启动混合 IO 压力 (4写+4读) ==="
sudo fio --name=write_stress --filename=/mnt/mixed_test/wfile \
  --ioengine=psync --rw=write --bs=64k --size=400M --numjobs=4 --direct=0 \
  --runtime=60 --output=/tmp/bdm_H_w.txt &
sudo fio --name=read_stress --filename=/mnt/mixed_test/rfile \
  --ioengine=libaio --iodepth=32 --rw=randread --bs=4k --size=400M --numjobs=4 --direct=1 \
  --runtime=60 --output=/tmp/bdm_H_r.txt &

sleep 10
echo "=== 混合 IO 运行中 ==="
iostat -x 1 3 2>/dev/null | tail -8

wait
echo "=== 完成 ==="

# 清理
sudo umount /mnt/mixed_test 2>/dev/null || true
sudo dmsetup remove mixed-dev 2>/dev/null || true
sudo losetup -d "$LOOP" 2>/dev/null || true
rm -f /tmp/mixed_dev.img
echo "=== 清理完毕 ==="
