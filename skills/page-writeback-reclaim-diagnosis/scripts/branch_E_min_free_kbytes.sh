#!/bin/bash
# ==============================================================
# branch_E_min_free_kbytes.sh
# 分支E：min_free_kbytes 不足
# 覆盖水位状态诊断、allocation failure 分析、
# min_free_kbytes 合理性评估、zone 水位失守检测
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支E：min_free_kbytes 不足诊断"
echo "=============================================================="

# 1. 当前 min_free_kbytes 与 MemFree
echo ""
echo "--- 1. 基础水位参数 ---"
min_free=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null || echo "N/A")
watermark_scale=$(cat /proc/sys/vm/watermark_scale_factor 2>/dev/null || echo "N/A")
watermark_boost=$(cat /proc/sys/vm/watermark_boost_factor 2>/dev/null || echo "N/A")
lowmem_reserve=$(cat /proc/sys/vm/lowmem_reserve_ratio 2>/dev/null || echo "N/A")
echo "  vm.min_free_kbytes = $min_free"
echo "  vm.watermark_scale_factor = $watermark_scale"
echo "  vm.watermark_boost_factor = $watermark_boost"
echo "  vm.lowmem_reserve_ratio = $lowmem_reserve"

free_kb=$(awk '/MemFree/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
total_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
echo "  MemFree: ${free_kb} kB"
echo "  MemTotal: ${total_kb} kB"

if [ "$min_free" != "N/A" ] && [ "$min_free" -gt 0 ] 2>/dev/null; then
    ratio=$(echo "scale=2; $free_kb / $min_free" | bc 2>/dev/null)
    echo "  MemFree/min_free_kbytes = ${ratio}x"
    if [ "$(echo "$ratio < 2" | bc 2>/dev/null)" = "1" ]; then
        echo "  [警告] MemFree 不足 min_free_kbytes 的 2 倍，水位紧张"
    fi
    min_ratio=$(echo "scale=4; $min_free * 100 / $total_kb" | bc 2>/dev/null)
    echo "  min_free_kbytes 占比: ${min_ratio}%"
fi

# 经典估算公式
if [ "$total_kb" -gt 0 ] 2>/dev/null; then
    classic_sug=$(echo "scale=0; sqrt($total_kb) * 4" | bc 2>/dev/null)
    echo "  经典估算建议: sqrt(${total_kb})*4 = ${classic_sug} kB"
    echo "  当前: ${min_free} kB"
fi

# 2. zoneinfo 水位状态
echo ""
echo "--- 2. zone 水位详细诊断 ---"
while IFS= read -r line; do
    echo "$line"
done < <(grep -E "Node|zone|free |min |low |high |present|spanned|protection|pagesets" /proc/zoneinfo 2>/dev/null | head -80)

# 分析每个 zone 的 free 与水位关系
echo ""
echo "--- 3. 逐 zone 水位诊断 ---"
awk '
  /^Node/ { node = $0; zone = "" }
  /zone/  { zone = $2 }
  /free / {
    if (zone != "") {
      free = $2;
      getline; if ($1 == "min") min = $2;
      getline; if ($1 == "low") low = $2;
      getline; if ($1 == "high") high = $2;
      printf "  %s %s: free=%d, min=%d, low=%d, high=%d\n", node, zone, free, min, low, high;
      if (free < min) printf "    [严重] free < min, 该 zone 已进入直接回收!\n";
      else if (free < low) printf "    [警告] free < low, kswapd 应已被唤醒\n";
      else if (free < high) printf "    [信息] free < high, kswapd 可持续回收\n";
      else printf "    [正常] free >= high\n";
      zone = "";
    }
  }
' /proc/zoneinfo 2>/dev/null

# 3. allocstall（分配 stall）指标
echo ""
echo "--- 4. allocstall / 分配延迟 ---"
for zone in dma dma32 normal movable; do
    val=$(awk -v z="$zone" '$1 == "allocstall_"z {print $2}' /proc/vmstat 2>/dev/null || echo 0)
    echo "  allocstall_${zone}: $val"
done

# 4. 检查 allocation failure 日志
echo ""
echo "--- 5. allocation failure 日志 ---"
dmesg 2>/dev/null | grep -iE "page allocation failure|allocation failure" | tail -20 || echo "（无 allocation failure 记录）"

# 5. order 分配统计
echo ""
echo "--- 6. /proc/buddyinfo 碎片状态 ---"
cat /proc/buddyinfo 2>/dev/null | head -10 || echo "/proc/buddyinfo 不可用"

# 6. 系统压测下的内存分配（如果是短等待）
echo ""
echo "--- 7. 内核日志关键错误 ---"
dmesg 2>/dev/null | grep -iE "blocked for|hung_task" | tail -10 || echo "（无 blocked task 记录）"

echo ""
echo "=============================================================="
echo " 分支E 诊断完成"
echo "=============================================================="
