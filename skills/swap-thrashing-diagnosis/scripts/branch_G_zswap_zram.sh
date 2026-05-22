#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_zswap_zram.sh
# 用途：zswap/zram 配置异常诊断
# 使用：bash branch_G_zswap_zram.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支G：zswap/zram 配置异常 —— 诊断分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 zswap 状态检查
# --------------------------------------------------------------------------
echo ""
echo "【M1】zswap 状态"

ZSWAP_FILE="${OUT_DIR}/zswap_zram.txt"
if [ -f "$ZSWAP_FILE" ]; then
  echo "------------------------------------------------------------------"
  grep -A50 "zswap debug" "$ZSWAP_FILE" 2>/dev/null | head -40
fi

echo ""

# 如果 zswap 不可用，直接提示
grep -q "zswap 未加载" "$ZSWAP_FILE" 2>/dev/null && ZSWAP_LOADED=false || ZSWAP_LOADED=true

if [ "$ZSWAP_LOADED" = false ]; then
  echo "  ⚠ zswap 未加载，跳过 zswap 分析"
  echo "  如果需要启用: modprobe zswap"
else
  echo ""
  echo "  zswap 关键指标分析:"
  echo "------------------------------------------------------------------"

  # 尝试获取 zswap 指标
  ZSWAP_PARAMS="/sys/module/zswap/parameters"
  ZSWAP_DEBUG="/sys/kernel/debug/zswap"

  if [ -d "$ZSWAP_DEBUG" ]; then
    STORED_PAGES=$(cat "$ZSWAP_DEBUG/stored_pages" 2>/dev/null || echo 0)
    COMPR_PAGES=$(cat "$ZSWAP_DEBUG/comp_pages" 2>/dev/null || echo 0)
    POOL_SIZE=$(cat "$ZSWAP_DEBUG/pool_total_size" 2>/dev/null || echo 0)
    REJECT_RECLAIM=$(cat "$ZSWAP_DEBUG/reject_reclaim_fail" 2>/dev/null || echo 0)
    REJECT_POOR=$(cat "$ZSWAP_DEBUG/reject_compress_poor" 2>/dev/null || echo 0)
    REJECT_ALLOC=$(cat "$ZSWAP_DEBUG/reject_alloc_fail" 2>/dev/null || echo 0)

    echo "    存储页数 (stored_pages):      ${STORED_PAGES}"
    echo "    压缩后页数 (comp_pages):      ${COMPR_PAGES}"
    echo "    池总大小 (pool_total_size):   ${POOL_SIZE} bytes"
    echo "    reject_reclaim_fail:          ${REJECT_RECLAIM}"
    echo "    reject_compress_poor:         ${REJECT_POOR}"
    echo "    reject_alloc_fail:            ${REJECT_ALLOC}"

    # 压缩率分析
    if [ "$STORED_PAGES" -gt 0 ] && [ "$COMPR_PAGES" -gt 0 ]; then
      RATIO=$(echo "scale=2; $COMPR_PAGES / $STORED_PAGES" | bc 2>/dev/null || echo "N/A")
      echo ""
      echo "    压缩率: ${RATIO}（越低越好，1.0 = 没压缩）"
      
      COMPR_SAVING=$(echo "scale=2; (1 - $COMPR_PAGES / $STORED_PAGES) * 100" | bc 2>/dev/null || echo "N/A")
      
      if [ "$(echo "$RATIO > 0.8" | bc 2>/dev/null)" = "1" ]; then
        echo "    🟡 压缩率偏低（> 0.8）→ 数据不可压缩或压缩算法不合适"
        echo "    建议: 检查压缩算法 (cat /sys/module/zswap/parameters/compressor)"
        echo "          尝试 zstd 替代 lzo（如果内核支持）"
      elif [ "$(echo "$RATIO > 0.5" | bc 2>/dev/null)" = "1" ]; then
        echo "    ░░ 压缩率中等（0.5-0.8）→ 可优化但非关键"
      else
        echo "    ✓ 压缩率高（< 0.5）→ zswap 在高效工作"
      fi
    else
      echo "    ⚠ 无有效 zswap 压缩数据（可能系统无 swap 活动）"
    fi

    # reject 分析
    echo ""
    if [ "$REJECT_RECLAIM" -gt 1000 ]; then
      echo "    ⚠ reject_reclaim_fail=${REJECT_RECLAIM} → zswap 在内存压力下回收失败"
      echo "    · 可能是 zswap 池太小"
      echo "    · 建议增大 zswap 内存占比: zswap.max_pool_percent=40"
    fi
    if [ "$REJECT_POOR" -gt 1000 ]; then
      echo "    ⚠ reject_compress_poor=${REJECT_POOR} → 很多页无法压缩"
      echo "    · 可能系统在处理已压缩/加密数据"
      echo "    · 检查是否有数据库/压缩文件被 swap out"
    fi
    if [ "$REJECT_ALLOC" -gt 100 ]; then
      echo "    ⚠ reject_alloc_fail=${REJECT_ALLOC} → zswap 内存不足"
      echo "    · 建议减小 zswap 池或增大系统内存"
    fi
  fi

  # zswap 参数检查
  if [ -d "$ZSWAP_PARAMS" ]; then
    echo ""
    echo "  zswap 内核参数:"
    for f in "$ZSWAP_PARAMS"/*; do
      echo "    $(basename $f) = $(cat $f 2>/dev/null)"
    done
  fi
fi

echo ""

# --------------------------------------------------------------------------
# M2 zram 状态检查
# --------------------------------------------------------------------------
echo ""
echo "【M2】zram 状态"
echo "------------------------------------------------------------------"

ZRAM_LOADED=false
if ls /sys/block/zram* &>/dev/null 2>/dev/null; then
  ZRAM_LOADED=true
fi

if [ "$ZRAM_LOADED" = true ]; then
  if command -v zramctl &>/dev/null; then
    echo "  zramctl 输出:"
    zramctl
  fi

  echo ""

  for zdev in /sys/block/zram*; do
    [ -d "$zdev" ] || continue
    DEV_NAME=$(basename "$zdev")

    DISKSIZE=$(cat "$zdev/disksize" 2>/dev/null || echo 0)
    MM_STAT=$(cat "$zdev/mm_stat" 2>/dev/null || echo "")
    COMP_ALGO=$(cat "$zdev/comp_algorithm" 2>/dev/null || echo "N/A")
    BACKING_DEV=$(cat "$zdev/backing_dev" 2>/dev/null || echo "none")

    echo "  --- ${DEV_NAME} ---"
    echo "    压缩算法: ${COMP_ALGO}"

    # mm_stat: orig_data_size compr_data_size mem_used_total mem_limit ...
    read -r ORIG COMPR USED REST <<< "$MM_STAT" 2>/dev/null || true
    if [ -n "$ORIG" ] && [ -n "$COMPR" ] && [ "$ORIG" -gt 0 ]; then
      ZRAM_RATIO=$(echo "scale=2; $COMPR / $ORIG" | bc 2>/dev/null || echo "N/A")
      ZRAM_SAVING=$(echo "scale=2; (1 - $COMPR / $ORIG) * 100" | bc 2>/dev/null || echo "N/A")

      echo "    原始数据大小: $ORIG bytes"
      echo "    压缩后大小:   $COMPR bytes"
      echo "    实际内存占用: $USED bytes"
      echo "    压缩比:       ${ZRAM_RATIO}（节省 ${ZRAM_SAVING}% 内存）"

      # 检查 zram 是否占用过多内存
      if [ -n "$USED" ] && [ "$USED" -gt 0 ]; then
        MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || echo 1)
        MEM_TOTAL=$(( MEM_TOTAL * 1024 ))  # kB -> bytes
        USED_PCT=$(echo "scale=2; $USED * 100 / $MEM_TOTAL" | bc 2>/dev/null || echo "N/A")
        echo "    zram 占用系统内存: ${USED_PCT}%"
        if [ "$(echo "$USED_PCT > 20" | bc 2>/dev/null)" = "1" ]; then
          echo "    ⚠ zram 占用过多系统内存（> 20%）"
          echo "    · 建议减小 zram 设备大小"
          echo "    · zram 大小建议为 RAM 的 25%-50%"
        fi
      fi
    else
      echo "    无有效数据（zram 可能为空）"
    fi

    echo "    后备设备: ${BACKING_DEV}"
    echo ""
  done
else
  echo "  zram 未加载"
  echo "  如需启用: modprobe zram && zramctl /dev/zram0 --algorithm lz4 --size 4G && mkswap /dev/zram0 && swapon /dev/zram0"
fi

echo ""

# --------------------------------------------------------------------------
# M3 内核语义分析 & 建议
# --------------------------------------------------------------------------
echo ""
echo "【M3】zswap/zram 配置优化建议"
echo "------------------------------------------------------------------"
cat << 'ADVICE'
  ┌────────────────────────────────────────────────────────────┐
  │  zswap vs zram 选择指南                                    │
  ├────────────────────────────────────────────────────────────┤
  │  zswap: 后端压缩缓存 + 后端 swap 设备                          │
  │    · 当内存压力小时: 压缩存储，不写入后端 swap                     │
  │    · 当内存压力大时: 解压后将页换出到后端 swap 设备               │
  │    · 优点: 减少实际 swap 设备写入                             │
  │    · 缺点: 内存压力大时增加 CPU 负载（压缩+解压）               │
  │                                                              │
  │  zram: 完全在内存中模拟 swap 设备（压缩存储）                   │
  │    · 直接在内存中压缩存储，不访问物理磁盘                        │
  │    · 优点: 极低延迟（比磁盘快 1000x+），无 IO 等待              │
  │    · 缺点: 占用系统内存（压缩后通常节省 50-75%）                │
  │                                                              │
  │  推荐场景:                                                    │
  │    · 内存充足 (> 32GB): zswap（作为 swap 缓存）                  │
  │    · 内存有限 (< 8GB):  zram（作为主 swap 设备）                │
  │    · SSD 寿命敏感:      zram（减少 SSD 写入）                   │
  │    · 延迟敏感:          zram（零 IO 等待）                      │
  └────────────────────────────────────────────────────────────┘

  调优参数:

  zswap:
    zswap.max_pool_percent=40     # 最大 zswap 池占内存百分比（默认 20%）
    zswap.zpool=zsmalloc          # 后端分配器（默认 zbud, zsmalloc 更高效）
    zswap.compressor=zstd         # 压缩算法（zstd 压缩比高，lz4 速度快）

  zram:
    # 大小建议: RAM * 25%-50%（不是 swap 方式的 2x）
    # 压缩算法: zstd（平衡压缩率和速度）或 lz4（更快的读写）
    # 建议同时设置 stream 数量 = CPU 核心数
    zramctl /dev/zram0 --algorithm zstd --size 4G
ADVICE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: zswap/zram 配置异常
  已检查项目:
    □ zswap 工作状态
    □ zswap 压缩率
    □ zswap reject 计数
    □ zram 压缩率
    □ zram 内存占用
    □ 算法配置
  
  建议:
    · 如果压缩率 > 0.8: 更换压缩算法或确认数据类型
    · 如果 reject 计数高: 调整 zswap 池大小
    · 如果 zram 占用内存 > 20%: 减小 zram 设备大小
    · 如需优化: 参考上方配置建议调整参数
CONCLUSION
