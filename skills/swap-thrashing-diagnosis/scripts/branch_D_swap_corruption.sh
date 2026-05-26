#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_swap_corruption.sh
# 用途：Swap 文件/分区损坏诊断
# 使用：bash branch_D_swap_corruption.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支D：Swap 文件/分区损坏 —— 诊断分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 dmesg I/O 错误检查
# --------------------------------------------------------------------------
echo ""
echo "【M1】内核 I/O 错误日志检查"
echo "------------------------------------------------------------------"

SWAP_INFO="${OUT_DIR}/swap_info.txt"
SWAP_DEV=$(awk 'NR>1{print $1}' "$SWAP_INFO" 2>/dev/null | head -1 || true)
SWAP_TYPE=$(awk 'NR>1{print $2}' "$SWAP_INFO" 2>/dev/null | head -1 || true)

echo "  Swap 设备: ${SWAP_DEV:-无}"
echo "  Swap 类型: ${SWAP_TYPE:-无}"
echo ""

# 检查 dmesg 错误
DMESG_FILE="${OUT_DIR}/dmesg_swap.txt"
if [ -f "$DMESG_FILE" ]; then
  echo "  dmesg 中的 I/O 错误:"
  ERRORS=$(grep -E "I/O error|buffer I/O|sd.*:.*error|nvme.*error" "$DMESG_FILE" 2>/dev/null || true)
  if [ -n "$ERRORS" ]; then
    echo "  ${ERRORS}"
    echo ""
    echo "  🚨 检测到 I/O 错误，可能原因:"
    echo "    · 磁盘/SSD 物理坏道或损坏"
    echo "    · 文件系统损坏"
    echo "    · 连接器松动或线缆故障"
  else
    echo "  ✓ 无明显 I/O 错误"
    if [ -z "$SWAP_DEV" ]; then
      echo "  ⚠ 注意: 未检测到 swap 设备，系统可能没有配置 swap"
    else
      echo "  如果需要更深度的检查，请检查 dmesg 的完整输出"
    fi
  fi
fi

echo ""

# --------------------------------------------------------------------------
# M2 Swap 文件完整性检查
# --------------------------------------------------------------------------
echo ""
echo "【M2】Swap 文件完整性检查"
echo "------------------------------------------------------------------"

if [ "${SWAP_TYPE}" = "file" ]; then
  SWAP_PATH="${SWAP_DEV}"
  echo "  Swap 文件路径: ${SWAP_PATH}"

  if [ -n "$SWAP_PATH" ] && [ -f "$SWAP_PATH" ]; then
    # 检查文件是否存在 hole（不连续区域）
    echo ""
    echo "  检查文件连续性:"
    if command -v filefrag &>/dev/null; then
      filefrag -v "$SWAP_PATH" 2>/dev/null | head -30
    else
      echo "  filefrag 不可用，请手动执行:"
      echo "  filefrag -v ${SWAP_PATH}"
    fi

    echo ""
    echo "  ➤ 观察要点:"
    echo "    · Swap 文件必须是连续的（extent count = 1）"
    echo "    · 如果 extent > 1 → 文件有 holes，内核无法使用"
    echo "    · Btrfs 不支持 swap 文件（需 NODATACOW）"
  else
    echo "  ⚠ Swap 文件不存在或不可访问: ${SWAP_PATH}"
  fi
elif [ "${SWAP_TYPE}" = "partition" ]; then
  echo "  Swap 分区: ${SWAP_DEV}"
  echo ""
  echo "  检查分区健康状态:"

  if [ -b "${SWAP_DEV}" ]; then
    # 检查分区是否有坏块（通过只读读取测试）
    echo "  执行分区健康读取检测（5秒采样）:"
    dd if="${SWAP_DEV}" of=/dev/null bs=4k count=10000 2>&1 || echo "  读取失败 -> 分区可能损坏"

    # 检查 smart 信息
    DEV_BASE=$(echo "$SWAP_DEV" | sed 's/[0-9]//g')
    if command -v smartctl &>/dev/null && [ -b "$DEV_BASE" ]; then
      echo ""
      echo "  SMART 健康信息:"
      smartctl -H "$DEV_BASE" 2>/dev/null | grep -E "SMART|PASSED|FAILED" || echo "  SMART 不可用（非 ATA/SCSI 设备）"
    fi
  else
    echo "  ⚠ 设备节点不存在: ${SWAP_DEV}"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# M3 内核语义分析
# --------------------------------------------------------------------------
echo ""
echo "【M3】内核语义分析 —— swap 损坏导致的异常行为"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  Swap 设备损坏的内核路径:

  读路径:
    do_swap_page() → swap_readpage() → 底层 block IO
      → 如果 IO 失败: 返回 -EIO
      → 内核将 swap 槽位标记为坏页
      → 如果该页有备份副本: 从其他源恢复
      → 如果没有备份: 可能导致应用段错误 (SIGSEGV)

  写路径:
    swap_writepage() → swap_write_cluster()
      → IO 错误 → 数据丢失
      → 脏页静默丢弃

  损坏检测:
    · swap_info_struct 中标志位记录
    · dmesg: "swap_info_get: bad swap entry" 
    · dmesg: "swap: swap_free: unhashed entry"

  修复步骤:
    1. 关闭 swap: swapoff -a
    2. 检查设备: badblocks -v /dev/sdX
    3. 重新创建 swap: mkswap /dev/sdX（分区）/ dd...mkswap（文件）
    4. 重新启用: swapon -a
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: Swap 文件/分区损坏
  处理建议:
    【紧急修复】
      1. 禁用损坏的 swap:
         swapoff <设备/文件路径>
      
      2. 如果是 swap 文件且不连续:
         创建新 swap 文件（确保连续）:
           dd if=/dev/zero of=/swapfile bs=1M count=4096
           chmod 600 /swapfile
           mkswap /swapfile
           swapon /swapfile
      
      3. 如果是分区损坏:
         badblocks -v <设备路径>
         若坏块太多，更换存储设备
    
    【验证建议】
      - 修复后重启系统
      - 确认 swapon 无报错
      - 观察 24h 无 I/O 错误
CONCLUSION
