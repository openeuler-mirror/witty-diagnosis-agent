#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_ssd_wear.sh
# 用途：Swap on SSD 磨损诊断
# 使用：bash branch_E_ssd_wear.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支E：Swap on SSD 磨损 —— 诊断分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 确认 Swap 设备
# --------------------------------------------------------------------------
echo ""
echo "【M1】Swap 设备识别与类型确认"
echo "------------------------------------------------------------------"

SWAP_INFO="${OUT_DIR}/swap_info.txt"
SWAP_DEV=$(awk 'NR>1{print $1}' "$SWAP_INFO" 2>/dev/null | head -1 || true)

if [ -z "$SWAP_DEV" ]; then
  echo "  未检测到 swap 设备"
  exit 0
fi

echo "  Swap 设备: ${SWAP_DEV}"

# 确认是否为 SSD
DEV_BASE=$(echo "$SWAP_DEV" | sed 's/[0-9]//g')
ROT_FILE="/sys/block/$(basename "$DEV_BASE")/queue/rotational"
SWAP_IS_SSD=false
if [ -f "$ROT_FILE" ]; then
  ROT=$(cat "$ROT_FILE")
  if [ "$ROT" = "0" ]; then
    SWAP_IS_SSD=true
    echo "  设备类型: ✅ SSD/NVMe（rotational=0）"
  else
    echo "  设备类型: HDD（rotational=1）— 本分支仅适用于 SSD"
    echo "  退出 SSD 磨损分析"
    exit 0
  fi
else
  echo "  无法确定设备类型 ($ROT_FILE 不存在)"
  echo "  若为 NVMe 设备，默认为 SSD"
  [ -d "/sys/block/$(basename "$DEV_BASE")" ] && SWAP_IS_SSD=true || true
fi

echo ""

# --------------------------------------------------------------------------
# M2 SSD 磨损量化
# --------------------------------------------------------------------------
echo ""
echo "【M2】SSD 磨损量化"
echo "------------------------------------------------------------------"

echo "  --- Swap 写入量估算 ---"
# 从 swapon 统计写入量（如果可用）
if [ -d "/sys/block/$(basename "$DEV_BASE")" ]; then
  STAT_FILE="/sys/block/$(basename "$DEV_BASE")/stat"
  if [ -f "$STAT_FILE" ]; then
    READ_IOS=$(awk '{print $1}' "$STAT_FILE")
    READ_SECTORS=$(awk '{print $3}' "$STAT_FILE")
    WRITE_IOS=$(awk '{print $5}' "$STAT_FILE")
    WRITE_SECTORS=$(awk '{print $7}' "$STAT_FILE")
    READ_GB=$(( READ_SECTORS * 512 / 1024 / 1024 / 1024 ))
    WRITE_GB=$(( WRITE_SECTORS * 512 / 1024 / 1024 / 1024 ))

    echo "  设备总 I/O (从启动至今):"
    echo "    读次数: ${READ_IOS}  读扇区: ${READ_SECTORS} (${READ_GB} GB)"
    echo "    写次数: ${WRITE_IOS}  写扇区: ${WRITE_SECTORS} (${WRITE_GB} GB)"
    echo ""
    echo "    ⚠ 注意: 这是整个设备的写入量，不限于 swap"
  fi
fi

echo ""
echo "  --- SMART 磨损信息 ---"
if command -v smartctl &>/dev/null; then
  smartctl -a "$DEV_BASE" 2>/dev/null | grep -E "Wear_Leveling|Total_LBAs_Written|Percentage Used|Media_Wearout|NAND_Writes|Lifetime" | head -10 || echo "  SMART 不可用或不支持此设备"
else
  echo "  smartctl 不可用，请安装 smartmontools"
  echo "  apt install smartmontools / yum install smartmontools"
fi

echo ""
echo "  ➤ 磨损评估:"
echo "    · Percentage Used > 10% → 建议关注"
echo "    · Percentage Used > 50% → 🔴 需考虑更换"
echo "    · 写入量 > 产品 TBW (Total Bytes Written) → 超寿命"
echo ""

# --------------------------------------------------------------------------
# M3 Swap 写入量 vs SSD 寿命评估
# --------------------------------------------------------------------------
echo ""
echo "【M3】Swap 对 SSD 寿命的影响评估"
echo "------------------------------------------------------------------"
cat << 'ANALYSIS'
  Swap on SSD 的影响因素:

  1. 写入模式:
     · swap 写入通常是 4K 随机写入（最差写入模式）
     · SSD 的写放大倍数 (WAF) 在 4K 随机下可达 10-50x
     · 意味着应用写 1KB，SSD 实际可能写 10-50KB

  2. 写入量估算:
     假设: so 平均 1000 pages/s, 每页 4K
     每秒钟写: 1000 * 4K = 4MB/s
     每天写:   4MB * 86400 = 345GB/天
     每月写:   345 * 30 ≈ 10TB/月

  3. SSD 寿命估算 (以 256GB TLC 为例):
     · DWPD (Drive Writes Per Day) = 0.3
     · 每日可写量: 256 * 0.3 = 76.8GB
     · 若 swap 写入 > 76.8GB/天 → 超出设计寿命
     · 预期寿命: 5 年 (NAND 写入寿命)

  4. 缓解方案:
     · 使用 ZRAM 替代 swap on SSD（压缩，减少写入）
     · 将 swap 移到 HDD 或专用低容量 SSD
     · 使用 Optane 等持久内存（P/E 周期极高）
     · 减少 swap 使用（调整 swappiness）
ANALYSIS

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: SSD 磨损风险（Swap on SSD）
  
  处理建议:
    【降低 swap 写入】
      1. 考虑使用 zram:
         modprobe zram
         zramctl /dev/zram0 --algorithm lz4 --size 4G
         mkswap /dev/zram0 && swapon /dev/zram0 -p 100
      2. 降低 swappiness:
         sysctl -w vm.swappiness=10
      3. 减少 swap 需求: 增加 RAM / 优化应用内存

    【延长 SSD 寿命】
      4. 确保 TRIM 启用: fstrim -av 或 systemctl enable fstrim.timer
      5. 预留 OP (Over-Provisioning): 分区时预留 10-20% 空间
      6. 使用 4K 对齐分区
    
    【硬件升级建议】
      7. 选择高 DWPD 的企业级 SSD
      8. 考虑 Optane 持久内存作为 swap 设备
CONCLUSION
