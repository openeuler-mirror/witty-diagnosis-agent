#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  bash collect_snapshot.sh --out <输出目录> [--iface <接口名>] [--dest <目标IP>] [--extra "<额外命令>"] [--since "<开始时间>"] [--until "<结束时间>"]

说明:
  - 该脚本用于"阶段一：快速信息收集（T0 快照）"，尽量并行采集网络与系统快照，降低人工遗漏。
  - 输出目录下会生成一个时间戳子目录，所有采集结果以 .txt 保存。

参数:
  --out   输出根目录(必填)。例如: ./out 或 /tmp/net_diag
  --iface 关注的接口(可选)。例如: eth0/bond0/vlan100
  --dest  关键目标IP(可选)。用于 ip route get / ping 快速探测
  --extra 额外命令(可选)。会在本机执行并保存输出
  --since 日志开始时间(可选)。格式: "2026-03-23 10:00"（推荐使用绝对时间）
  --until 日志结束时间(可选)。格式同 --since

时间参数说明:
  - --since/--until 用于筛选 journalctl 日志，适用于诊断历史故障
  - 若不指定，默认采集最近 300 行日志（适用于当前正在发生的故障）
  - 推荐使用绝对时间格式: "YYYY-MM-DD HH:MM"
  - 示例:
    --since "2026-03-23 10:00" --until "2026-03-23 11:00"  # 推荐：绝对时间
    --since "2026-03-22 12:00" --until "2026-03-22 18:00"  # 推荐：昨天下午

示例:
  # 当前故障诊断（默认采集最近日志）
  bash collect_snapshot.sh --out ./out --iface bond0 --dest 10.0.0.1

  # 历史故障诊断（指定故障时间段）
  bash collect_snapshot.sh --out ./out --since "2026-03-23 10:00" --until "2026-03-23 11:00"
EOF
}

OUT_ROOT=""
IFACE=""
DEST=""
EXTRA_CMD=""
SINCE=""
UNTIL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_ROOT="${2:-}"; shift 2 ;;
    --iface) IFACE="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    --extra) EXTRA_CMD="${2:-}"; shift 2 ;;
    --since) SINCE="${2:-}"; shift 2 ;;
    --until) UNTIL="${2:-}"; shift 2 ;;
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
else
  echo "=== 收集所有活跃接口的 ethtool 信息 ==="
  for iface in $(ip -o link show 2>/dev/null | awk '/UP/ {gsub(/:/,"",$2); print $2}'); do
    run_sh "iface_${iface}_details" "ip -d link show ${iface} 2>/dev/null || true; echo; ethtool ${iface} 2>/dev/null || true; echo; ethtool -S ${iface} 2>/dev/null || true"
  done
fi

# 3) 路由/策略路由/邻居表
run_sh "ip_route_main" "ip route show table main 2>/dev/null || netstat -rn"
run_sh "ip_route_all" "ip route show table all 2>/dev/null || true"
run_sh "ip_rule" "ip rule show 2>/dev/null || true"
run_sh "ip_neigh" "ip neigh show 2>/dev/null || arp -an"

# 3.4) ARP 表状态检测（FM_NET_003）
{
  file="${out_dir}/arp_table_status.txt"
  {
    echo "## cmd: ARP table status check"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo

    echo "=== ARP 条目统计 ==="
    total_entries=$(ip neigh show 2>/dev/null | wc -l)
    echo "总条目数: ${total_entries}"
    echo

    echo "=== 各状态条目数 ==="
    ip neigh show 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn
    echo

    echo "=== 各接口 ARP 条目数 ==="
    ip neigh show 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn
    echo

    echo "=== ARP 表上限配置 (gc_thresh) ==="
    echo "gc_thresh1 (最小保留): $(cat /proc/sys/net/ipv4/neigh/default/gc_thresh1 2>/dev/null || echo 'N/A')"
    echo "gc_thresh2 (软上限): $(cat /proc/sys/net/ipv4/neigh/default/gc_thresh2 2>/dev/null || echo 'N/A')"
    echo "gc_thresh3 (硬上限): $(cat /proc/sys/net/ipv4/neigh/default/gc_thresh3 2>/dev/null || echo 'N/A')"
    echo

    thresh3=$(cat /proc/sys/net/ipv4/neigh/default/gc_thresh3 2>/dev/null || echo 0)
    if [[ "${thresh3}" -gt 0 ]]; then
      usage_pct=$((total_entries * 100 / thresh3))
      echo "=== 使用率评估 ==="
      echo "当前条目: ${total_entries}"
      echo "硬上限: ${thresh3}"
      echo "使用率: ${usage_pct}%"
      if [[ ${usage_pct} -ge 90 ]]; then
        echo "状态: ⚠️ ARP 表接近满载，可能导致新连接无法建立"
      elif [[ ${usage_pct} -ge 70 ]]; then
        echo "状态: ⚡ ARP 表使用率较高，建议关注"
      else
        echo "状态: ✅ 正常"
      fi
    fi
    echo

    echo "=== 内核 ARP 相关参数 ==="
    echo "gc_interval: $(cat /proc/sys/net/ipv4/neigh/default/gc_interval 2>/dev/null || echo 'N/A')"
    echo "gc_stale_time: $(cat /proc/sys/net/ipv4/neigh/default/gc_stale_time 2>/dev/null || echo 'N/A')"
    echo "base_reachable_time_ms: $(cat /proc/sys/net/ipv4/neigh/default/base_reachable_time_ms 2>/dev/null || echo 'N/A')"
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

# 6.5) conntrack 状态检测（FM_NET_007）
{
  file="${out_dir}/conntrack_status.txt"
  {
    echo "## cmd: conntrack status check"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo

    echo "=== conntrack 条目统计 ==="
    current_count=$(conntrack -L 2>/dev/null | wc -l || echo 0)
    echo "当前条目数: ${current_count}"
    echo

    echo "=== conntrack 上限配置 ==="
    max_count=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 'N/A')
    echo "nf_conntrack_max: ${max_count}"
    echo

    if [[ "${max_count}" != "N/A" && "${max_count}" -gt 0 ]]; then
      usage_pct=$((current_count * 100 / max_count))
      echo "=== 使用率评估 ==="
      echo "当前条目: ${current_count}"
      echo "上限: ${max_count}"
      echo "使用率: ${usage_pct}%"
      if [[ ${usage_pct} -ge 90 ]]; then
        echo "状态: ⚠️ conntrack 表接近满载，新连接可能无法建立"
      elif [[ ${usage_pct} -ge 70 ]]; then
        echo "状态: ⚡ conntrack 使用率较高，建议关注"
      else
        echo "状态: ✅ 正常"
      fi
    fi
    echo

    echo "=== conntrack 内核参数 ==="
    echo "nf_conntrack_buckets: $(cat /proc/sys/net/netfilter/nf_conntrack_buckets 2>/dev/null || echo 'N/A')"
    echo "nf_conntrack_count: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 'N/A')"
    echo "nf_conntrack_tcp_timeout_established: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established 2>/dev/null || echo 'N/A')"
    echo "nf_conntrack_tcp_timeout_time_wait: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait 2>/dev/null || echo 'N/A')"
    echo "nf_conntrack_tcp_timeout_close_wait: $(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close_wait 2>/dev/null || echo 'N/A')"
    echo

    echo "=== conntrack 统计信息 ==="
    cat /proc/net/stat/nf_conntrack 2>/dev/null | head -n 5 || echo "N/A"
  } >"${file}" 2>&1
}

# 7) 内核/系统日志（支持时间窗口筛选）
{
  file="${out_dir}/dmesg_log.txt"
  {
    echo "## cmd: dmesg with time filter"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    if [[ -n "${SINCE}" || -n "${UNTIL}" ]]; then
      echo "## filter: since=${SINCE:-N/A} until=${UNTIL:-N/A}"
    fi
    echo

    if [[ -n "${SINCE}" || -n "${UNTIL}" ]]; then
      echo "=== 按时间窗口筛选 dmesg 日志 ==="
      since_ts=$(date -d "${SINCE}" +%s 2>/dev/null || echo 0)
      until_ts=$(date -d "${UNTIL}" +%s 2>/dev/null || echo 9999999999)
      dmesg -T 2>/dev/null | awk -v since="$since_ts" -v until="$until_ts" '
        match($0, /^\[([A-Za-z]+ [A-Za-z]+ [0-9]+ [0-9:]+ [0-9]+)\]/, arr) {
          cmd = "date -d \"" arr[1] "\" +%s 2>/dev/null"
          cmd | getline ts
          close(cmd)
          if (ts >= since && ts <= until) print $0
        }
      ' || true
    else
      echo "=== 最近 300 行内核日志 ==="
      dmesg -T 2>/dev/null | tail -n 300 || true
    fi
  } >"${file}" 2>&1
}

{
  file="${out_dir}/journal_kernel.txt"
  {
    echo "## cmd: journalctl kernel logs"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    if [[ -n "${SINCE}" || -n "${UNTIL}" ]]; then
      echo "## filter: since=${SINCE:-N/A} until=${UNTIL:-N/A}"
    fi
    echo

    if [[ -n "${SINCE}" || -n "${UNTIL}" ]]; then
      echo "=== 按时间窗口筛选内核日志 ==="
      journalctl -k --since="${SINCE:-}" --until="${UNTIL:-}" 2>/dev/null || true
    else
      echo "=== 最近 300 行内核日志 ==="
      journalctl -k -n 300 2>/dev/null || true
    fi
  } >"${file}" 2>&1
}

if [[ -n "${SINCE}" || -n "${UNTIL}" ]]; then
  {
    file="${out_dir}/journal_system_window.txt"
    echo "## cmd: journalctl system logs (time window)"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo "## filter: since=${SINCE:-N/A} until=${UNTIL:-N/A}"
    echo
    echo "=== 按时间窗口筛选系统日志 ==="
    journalctl --since="${SINCE:-}" --until="${UNTIL:-}" 2>/dev/null || true
  } >"${file}" 2>&1
fi

# 8) 关键目标快速探测
if [[ -n "${DEST}" ]]; then
  run_sh "route_get_${DEST}" "ip route get ${DEST} 2>/dev/null || true"
  run_sh "ping_${DEST}" "ping -c 3 -W 1 ${DEST} 2>/dev/null || ping -c 3 ${DEST} 2>/dev/null || true"
fi

# 8.5) MTU 配置与探测（FM_NET_006）
{
  file="${out_dir}/mtu_status.txt"
  {
    echo "## cmd: MTU status check"
    echo "## time: $(date -Is)"
    echo "## host: $(hostname)"
    echo

    echo "=== 各接口 MTU 配置 ==="
    ip -o link show 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="mtu"){print $2" MTU="$(i+1)}}}' | tr -d ':'
    echo

    echo "=== 默认 MTU 参数 ==="
    echo "tcp_mtu_probing: $(cat /proc/sys/net/ipv4/tcp_mtu_probing 2>/dev/null || echo 'N/A')"
    echo "tcp_base_mss: $(cat /proc/sys/net/ipv4/tcp_base_mss 2>/dev/null || echo 'N/A')"
    echo

    if [[ -n "${DEST}" ]]; then
      echo "=== MTU 路径探测 (目标: ${DEST}) ==="
      echo "说明: 使用 ping -M do -s <size> 探测最大无分片包大小"
      echo

      out_iface=$(ip route get "${DEST}" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1); exit}}}')
      if [[ -n "${out_iface}" ]]; then
        iface_mtu=$(ip link show "${out_iface}" 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="mtu"){print $(i+1); exit}}}')
        echo "出接口: ${out_iface}"
        echo "接口 MTU: ${iface_mtu:-N/A}"
        echo

        if [[ -n "${iface_mtu}" && "${iface_mtu}" -gt 28 ]]; then
          max_payload=$((iface_mtu - 28))
          echo "理论最大 payload: ${max_payload} (MTU - 28字节 IP+ICMP 头)"
          echo

          echo "--- 测试常见 MTU 值 ---"
          for test_mtu in 1500 1400 1300 1200 1000 800 576; do
            if [[ ${test_mtu} -le ${iface_mtu} ]]; then
              payload=$((test_mtu - 28))
              echo -n "MTU ${test_mtu} (payload ${payload}): "
              if ping -M do -s ${payload} -c 1 -W 2 "${DEST}" >/dev/null 2>&1; then
                echo "✅ 通过"
              else
                echo "❌ 需要分片"
              fi
            fi
          done
        fi
      else
        echo "无法确定到 ${DEST} 的出接口"
      fi
    else
      echo "提示: 未指定 --dest 参数，跳过 MTU 路径探测"
      echo "如需探测 MTU，请使用: --dest <目标IP>"
    fi
  } >"${file}" 2>&1
}

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
日志已收集到 ${out_dir} 目录，可直接在该目录下进行诊断分析。
EOF

