#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_helper_alg.sh
# 用途：helper/ALG 协议辅助模块故障分析
#       当 FTP/SIP/TFTP/PPTP 等需要 ALG 辅助的协议连接异常时使用
# 使用：bash branch_G_helper_alg.sh [基线采集目录]
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-/tmp/netfilter_diag_*}"
if [[ "$BASE_DIR" == *"*"* ]]; then
    BASE_DIR=$(ls -dt /tmp/netfilter_diag_* 2>/dev/null | head -1)
fi
if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
    echo "错误：请先执行 01_collect_baseline.sh，然后传入其输出目录"
    echo "使用：bash branch_G_helper_alg.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支G：helper/ALG 协议辅助模块故障"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step G1: 已加载的 nf_conntrack helper 模块 ----
echo ""
echo "【G1】已加载的 conntrack helper 模块"
echo "------------------------------------------------------------------"
lsmod | grep -E "nf_conntrack|nf_ct" | sort || echo "(无相关模块)"

echo ""
echo "[已注册的 helper]"
if [[ -d /proc/sys/net/netfilter/nf_conntrack_helper ]]; then
    cat /proc/sys/net/netfilter/nf_conntrack_helper 2>/dev/null \
        && echo "(1=自动 helper 分配开启)"
elif [[ -f /proc/sys/net/netfilter/nf_conntrack_helper ]]; then
    cat /proc/sys/net/netfilter/nf_conntrack_helper
fi

# 列出可用 helper
for helper_path in /proc/sys/net/netfilter/nf_ct_helper_*; do
    if [[ -f "$helper_path" ]]; then
        echo "  $(basename $helper_path): $(cat $helper_path 2>/dev/null || echo 'N/A')"
    fi
done 2>/dev/null || true

# ---- Step G2: iptables/nftables helper 规则检查 ----
echo ""
echo "【G2】helper/ALG 相关规则检查"
echo "------------------------------------------------------------------"
echo "[iptables helper 匹配规则]"
for f in "${BASE_DIR}/ruleset"/iptables_*.txt; do
    [[ -f "$f" ]] || continue
    table=$(basename "$f" .txt)
    matches=$(grep -E "helper|alg|ftp|sip|tftp|pptp|h323|irc" "$f" || true)
    if [[ -n "$matches" ]]; then
        echo "  [${table}]"
        echo "$matches" | sed 's/^/    /'
    fi
done

echo ""
echo "[nftables helper 相关]"
if [[ -f "${BASE_DIR}/ruleset/nftables_ruleset.txt" ]]; then
    grep -iE "helper|alg|ftp|sip|tftp|pptp" "${BASE_DIR}/ruleset/nftables_ruleset.txt" \
        | head -20 || echo "  (无 helper 相关规则)"
fi

# ---- Step G3: 常见 ALG 问题诊断 ----
echo ""
echo "【G3】常见 ALG 问题诊断"
echo "------------------------------------------------------------------"
cat <<'ALG'
[各协议 ALG 问题诊断]

1. FTP (nf_conntrack_ftp)
   - 症状: 数据通道(PORT/PASV)无法建立
   - 检查: lsmod | grep nf_conntrack_ftp
   - 检查: iptables 是否需要 "-m helper --helper ftp"
   - 注意: 主动模式 PORT 需要 nf_conntrack_ftp，被动模式 PASV 也需要

2. SIP (nf_conntrack_sip)
   - 症状: VoIP 通话无法建立或单向音频
   - 检查: lsmod | grep nf_conntrack_sip
   - 检查: SIP 信令端口是否与 sip_timeout 匹配

3. TFTP (nf_conntrack_tftp)
   - 症状: TFTP 数据传输失败
   - 检查: lsmod | grep nf_conntrack_tftp

4. PPTP (nf_conntrack_pptp)
   - 症状: VPN 连接建立失败
   - 检查: lsmod | grep nf_conntrack_pptp
   - 检查: GRE 协议(47)是否被防火墙放行

5. H.323 (nf_conntrack_h323)
   - 症状: 视频会议连接失败
   - 检查: lsmod | grep nf_conntrack_h323

6. IRC (nf_conntrack_irc)
   - 症状: DCC 文件传输失败
   - 检查: lsmod | grep nf_conntrack_irc

通用排查步骤:
  1. 确认 nf_conntrack_helper=1(自动分配)或规则中显式使用 helper
  2. 确认对应 helper 模块已加载 (modprobe nf_conntrack_xxx)
  3. 确认防火墙放行了控制通道端口
  4. 如果使用 nftables，确认 ct helper 设置正确
  5. 检查 conntrack 是否有 EXPECTED/RELATED 条目
ALG

echo ""
echo "请参考 references/conntrack_reference.md 中 helper/ALG 相关章节完成深入分析。"
