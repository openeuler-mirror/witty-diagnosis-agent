#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  bash collect_snapshot.sh --out <输出目录> [--iface <接口名>] [--dest <目标IP>] [--extra "<额外命令>"]

说明:
  - 该脚本用于“阶段一：快速信息收集（T0 快照）”，尽量并行采集网络与系统快照，降低人工遗漏。
  - 输出目录下会生成一个时间戳子目录，所有采集结果以 .txt 保存。

参数:
  --out   输出根目录(必填)。例如: ./out 或 /tmp/net_diag
  --iface 关注的接口(可选)。例如: eth0/bond0/vlan100
  --dest  关键目标IP(可选)。用于 ip route get / ping 快速探测
  --extra 额外命令(可选)。会在本机执行并保存输出

示例:
  bash collect_snapshot.sh --out ./out --iface bond0 --dest 10.0.0.1
EOF
}

OUT_ROOT=""
IFACE=""
DEST=""
EXTRA_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_ROOT="${2:-}"; shift 2 ;;
    --iface) IFACE="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    --extra) EXTRA_CMD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "${OUT_ROOT}" ]]; then
  echo "--out 必填" >&2
  usage
  exit 2
fi

ts="$(date +%Y%m%d_%H%M%S)"
out_dir="${OUT_ROOT%/}/snapshot_${ts}"
mkdir -p "${out_dir}"

run() {
  local name="$1"
  shift
  local file="${out_dir}/${name}.txt"
  {
    echo "## cmd: $*"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo
    "$@"
  } >"${file}" 2>&1
}

run_sh() {
  local name="$1"
  local cmd="$2"
  local file="${out_dir}/${name}.txt"
  {
    echo "## cmd: ${cmd}"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo
    bash -lc "${cmd}"
  } >"${file}" 2>&1
}

echo "输出目录: ${out_dir}"

# 1) 基本身份/时间/系统负载
run_sh "system_basic" "uname -a; echo; uptime; echo; date -Is; echo; whoami"
run_sh "process_top" "top -bn1 2>/dev/null | head -n 30 || top -l 1 | head -n 30"
run_sh "memory" "free -m 2>/dev/null || vm_stat"

# 2) 接口/地址/链路统计
run_sh "ip_addr" "ip addr 2>/dev/null || ifconfig -a"
run_sh "ip_link_stats" "ip -s link 2>/dev/null || netstat -i"
run_sh "mac_duplicate_check" "ip -o link 2>/dev/null | awk 'match(\$0,/^[0-9]+: [^:]+:/){iface=substr(\$0,RSTART,RLENGTH); sub(/^[0-9]+: /,\"\",iface); sub(/:$/,\"\",iface)} match(\$0,/link\\/ether [0-9a-fA-F:]{17}/){mac=substr(\$0,RSTART+11,17); mac=tolower(mac); list[mac]=list[mac]\" \"iface; cnt[mac]++} END{dup=0; for(m in cnt){if(cnt[m]>1){print \"DUP_MAC\",m,list[m]; dup=1}} if(!dup) print \"NO_DUP_MAC\"}'"
run_sh "mac_duplicate" "ip -o link 2>/dev/null | awk 'match(\$0,/^[0-9]+: [^:]+:/){iface=substr(\$0,RSTART,RLENGTH); sub(/^[0-9]+: /,\"\",iface); sub(/:$/,\"\",iface)} match(\$0,/link\\/ether [0-9a-fA-F:]{17}/){mac=substr(\$0,RSTART+11,17); mac=tolower(mac); list[mac]=list[mac]\" \"iface; cnt[mac]++} END{for(m in cnt){if(cnt[m]>1){print m,list[m]}}}'"

if [[ -n "${IFACE}" ]]; then
  run_sh "iface_${IFACE}_details" "ip -d link show ${IFACE} 2>/dev/null || true; echo; ethtool ${IFACE} 2>/dev/null || true; echo; ethtool -S ${IFACE} 2>/dev/null || true"
fi

# 3) 路由/策略路由/邻居表
run_sh "ip_route_main" "ip route show table main 2>/dev/null || netstat -rn"
run_sh "ip_route_all" "ip route show table all 2>/dev/null || true"
run_sh "ip_rule" "ip rule show 2>/dev/null || true"
run_sh "ip_neigh" "ip neigh show 2>/dev/null || arp -an"

# 3.5) IP 冲突探测（尽量不失败）
{
  file="${out_dir}/ip_conflict_check.txt"
  {
    echo "## cmd: arping -D -I <iface> <ip>"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo

    if ! command -v arping >/dev/null 2>&1; then
      echo "SKIP: arping 未安装，无法执行主动 IP 冲突探测。"
      echo "建议安装 arping 后重试，或在阶段二手工执行: arping -D -I <iface> <ip>"
      exit 0
    fi

    if [[ -n "${IFACE}" ]]; then
      mapfile -t pairs < <(ip -o -4 addr show dev "${IFACE}" 2>/dev/null | awk '{print $2" "$4}')
      if [[ ${#pairs[@]} -eq 0 ]]; then
        echo "NO_IPV4_ON_IFACE: ${IFACE}"
      fi
    else
      mapfile -t pairs < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2" "$4}')
      if [[ ${#pairs[@]} -eq 0 ]]; then
        echo "NO_GLOBAL_IPV4_ADDR"
      fi
    fi

    for pair in "${pairs[@]:-}"; do
      iface="$(awk '{print $1}' <<<"${pair}")"
      cidr="$(awk '{print $2}' <<<"${pair}")"
      ip="${cidr%/*}"
      if [[ -z "${iface}" || -z "${ip}" ]]; then
        continue
      fi

      echo "== CHECK iface=${iface} ip=${ip} =="
      if arping -D -c 2 -w 2 -I "${iface}" "${ip}"; then
        echo "NO_CONFLICT_DETECTED iface=${iface} ip=${ip}"
      else
        rc=$?
        echo "POTENTIAL_CONFLICT_OR_CHECK_FAILED iface=${iface} ip=${ip} rc=${rc}"
        echo "请结合输出日志判断：若出现 reply received，通常表示存在 IP 冲突。"
      fi
      echo
    done
  } >"${file}" 2>&1
}

# 4) DNS
run_sh "dns_resolv_conf" "cat /etc/resolv.conf 2>/dev/null || true"
run_sh "dns_nsswitch" "cat /etc/nsswitch.conf 2>/dev/null | sed -n '1,120p' || true"

# 5) 连接状态/统计/监听
run_sh "ss_ant" "ss -ant 2>/dev/null || netstat -ant"
run_sh "ss_s" "ss -s 2>/dev/null || netstat -s"
run_sh "ss_listen" "ss -lntp 2>/dev/null || netstat -lntp"

# 6) 防火墙/conntrack（尽量不失败）
run_sh "firewall_iptables" "iptables -L -n -v 2>/dev/null || true"
run_sh "firewall_nft" "nft list ruleset 2>/dev/null || true"
run_sh "conntrack_count" "conntrack -L 2>/dev/null | wc -l || true"

# 7) 内核/系统日志（取近期窗口）
run_sh "dmesg_tail_300" "dmesg 2>/dev/null | tail -n 300 || true"
run_sh "journal_k_tail_300" "journalctl -k -n 300 2>/dev/null || true"

# 8) 关键目标快速探测
if [[ -n "${DEST}" ]]; then
  run_sh "route_get_${DEST}" "ip route get ${DEST} 2>/dev/null || true"
  run_sh "ping_${DEST}" "ping -c 3 -W 1 ${DEST} 2>/dev/null || ping -c 3 ${DEST} 2>/dev/null || true"
fi

# 9) 额外命令
if [[ -n "${EXTRA_CMD}" ]]; then
  run_sh "extra" "${EXTRA_CMD}"
fi

# 并行化：上面 run_sh 都是同步写文件；为了不引入复杂度，这里提供一个“任务并发模板”
# 如果需要更强并行，可将 run_sh 调用改为：
#   run_sh "name" "cmd" &  并在末尾 wait
#
# 当前版本强调可移植性和可读性；实际收集命令本身很快，通常已足够。

cat <<EOF
完成。
你可以把 ${out_dir} 整个目录打包给诊断流程使用。
EOF

