#!/usr/bin/env bash
# IP 冲突检测脚本
# 用法: bash ip_conflict_check.sh [--iface <接口名>] [--ip <IP地址>]
# 输出: 检测结果和最终结论

set -euo pipefail

IFACE=""
TARGET_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iface) IFACE="${2:-}"; shift 2 ;;
    --ip) TARGET_IP="${2:-}"; shift 2 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

echo "## cmd: IP conflict detection"
echo "## time: $(date -Is)"
echo "## host: $(hostname)"
echo

if ! command -v arping >/dev/null 2>&1; then
  echo "SKIP: arping 未安装，无法执行主动 IP 冲突探测。"
  echo "建议安装 arping 后重试，或手工执行: arping -D -I <iface> <ip>"
  exit 0
fi

echo "=== 本机接口 MAC 地址列表 ==="
declare -A iface_macs
while IFS= read -r line; do
    if [[ -z "$line" ]]; then
        continue
    fi
    iface=$(echo "$line" | awk '{print $1}')
    mac=$(echo "$line" | awk '{print $2}')
    if [[ -n "$iface" && -n "$mac" ]]; then
        iface_macs["$iface"]="$mac"
        echo "  $iface: ${mac^^}"
    fi
done < <(ip -o link 2>/dev/null | awk '/link\/ether/ {
  iface=$2
  gsub(/:$/, "", iface)
  for(i=1;i<=NF;i++) {
    if($i=="link/ether") {
      mac=$(i+1)
      print iface, mac
      break
    }
  }
}')
echo

get_ip_list() {
    if [[ -n "${IFACE}" ]]; then
        ip -o -4 addr show dev "${IFACE}" 2>/dev/null | awk '{print $4}' | cut -d'/' -f1
    else
        ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d'/' -f1
    fi
}

if [[ -n "${TARGET_IP}" ]]; then
    ip_list=("${TARGET_IP}")
else
    mapfile -t ip_list < <(get_ip_list)
fi

if [[ ${#ip_list[@]} -eq 0 ]]; then
    echo "NO_IPV4_ADDR_TO_CHECK"
    exit 0
fi

conflict_list=()
no_conflict_list=()

check_ip_conflict() {
    local ip="$1"
    local iface="$2"
    
    echo "== 检测 ${ip} (接口: ${iface}) =="
    
    local current_mac="${iface_macs[$iface]:-}"
    echo "本接口 MAC: ${current_mac^^}"
    
    local arping_output
    local arping_rc=0
    arping_output=$(arping -D -c 2 -w 2 -I "${iface}" "${ip}" 2>&1) || arping_rc=$?
    
    if [[ $arping_rc -eq 0 ]]; then
        echo "检测结果: ✅ 无冲突"
        no_conflict_list+=("${ip}@${iface}")
        return 0
    fi
    
    local response_mac
    response_mac=$(echo "$arping_output" | grep -oP '\[[0-9a-fA-F:]{17}\]' | head -1 | tr -d '[]' | tr '[:upper:]' '[:lower:]')
    
    if [[ -z "$response_mac" ]]; then
        echo "检测结果: ⚠️ 检测失败 (arping 返回码: ${arping_rc})"
        return 1
    fi
    
    local response_iface=""
    for i in "${!iface_macs[@]}"; do
        if [[ "${iface_macs[$i]}" == "$response_mac" ]]; then
            response_iface="$i"
            break
        fi
    done
    
    if [[ -z "$response_iface" ]]; then
        echo "响应 MAC: ${response_mac^^}"
        echo "检测结果: ❌ 存在 IP 冲突"
        echo "冲突设备 MAC: ${response_mac^^}"
        conflict_list+=("${ip}@${iface} (冲突MAC: ${response_mac^^})")
        return 2
    else
        echo "检测结果: ✅ 无冲突"
        no_conflict_list+=("${ip}@${iface}")
        return 0
    fi
}

for ip in "${ip_list[@]}"; do
    if [[ -z "$ip" ]]; then
        continue
    fi
    
    if [[ -n "${IFACE}" ]]; then
        check_ip_conflict "$ip" "${IFACE}" || true
    else
        iface_for_ip=$(ip -o -4 addr show 2>/dev/null | grep " ${ip}/" | awk '{print $2}' | head -1)
        if [[ -n "$iface_for_ip" ]]; then
            check_ip_conflict "$ip" "$iface_for_ip" || true
        fi
    fi
    echo
done

echo "=========================================="
echo "=== 最终结论 ==="
echo "=========================================="
echo

if [[ ${#conflict_list[@]} -eq 0 ]]; then
    echo "✅ 结论: 无 IP 冲突"
    echo
    echo "已检测 ${#no_conflict_list[@]} 个 IP 地址，均无冲突。"
else
    echo "❌ 结论: 存在 IP 冲突"
    echo
    echo "冲突 IP 列表:"
    for item in "${conflict_list[@]}"; do
        echo "  - $item"
    done
    echo
    echo "建议处理: 定位冲突设备并修改其 IP 地址"
fi
