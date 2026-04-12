#!/bin/bash
# =================================================================
# Name: time_master_diag.sh
# Version: 2.1 (Expert SRE Edition)
# Description: 工业级时间同步故障诊断脚本 (增强路径鲁棒性与双栈审计)
# =================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

LOG_FILE="/tmp/time_full_diag_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

function show_help() {
    echo "Usage: sudo bash $0"
    echo "场景覆盖: A.服务冲突 B.管理通道(含IPv6) C.链路通断 D.内核时钟 E.协议逻辑"
}

[[ "$1" == "-h" || "$1" == "--help" ]] && show_help && exit 0

echo -e "${YELLOW}=== [1. 基础环境与配置文件探测] ===${NC}"
# 1.1 动态定位配置文件路径
CHRONY_CONF="/etc/chrony.conf"
if pgrep -x "chronyd" > /dev/null; then
    # 尝试从运行进程中提取配置文件路径
    PROC_CONF=$(ps -ef | grep chronyd | grep -v grep | sed -n 's/.*-f \([^ ]*\).*/\1/p')
    [ -n "$PROC_CONF" ] && CHRONY_CONF="$PROC_CONF"
fi
# 常见备选路径检查
[ ! -f "$CHRONY_CONF" ] && [ -f "/etc/chrony/chrony.conf" ] && CHRONY_CONF="/etc/chrony/chrony.conf"

if [ -f "$CHRONY_CONF" ]; then
    echo -e "正在使用配置文件: ${GREEN}$CHRONY_CONF${NC}"
else
    echo -e "${RED}[WARN] 未能定位到标准的 chrony.conf，部分网络审计可能受限${NC}"
fi

# 1.2 检查服务竞争
ACTIVE_SVCS=()
SERVICES=("ntpd" "chronyd" "systemd-timesyncd")
for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
        echo -e "[ACTIVE] $svc 正在运行"
        ACTIVE_SVCS+=("$svc")
    fi
done

if [ ${#ACTIVE_SVCS[@]} -gt 1 ]; then
    echo -e "${RED}[CRITICAL] 发现多个同步服务冲突: ${ACTIVE_SVCS[*]}${NC}"
fi

echo -e "\n${YELLOW}=== [2. 网络与 DNS 连通性] ===${NC}"
# 递归提取所有上游服务器 (包含对 pool 和 server 的解析)
if [ -f "$CHRONY_CONF" ]; then
    SERVERS=$(grep -E "^(server|pool)" "$CHRONY_CONF" | awk '{print $2}' | grep -v '127.0.0.1' | sort -u)
fi

if [ -z "$SERVERS" ]; then
    echo -e "${YELLOW}[INFO] 未从配置中提取到远程服务器，可能是默认配置或使用了 include 指令${NC}"
else
    for s in $SERVERS; do
        echo -n "检测 $s : "
        # DNS 解析检查
        if ! getent hosts "$s" > /dev/null; then
            echo -e "${RED}DNS_FAIL${NC}"
            continue
        fi
        # UDP 123 探测
        if command -v nc &>/dev/null; then
            nc -zu -w 2 "$s" 123 &>/dev/null && echo -e "${GREEN}UDP_OK${NC}" || echo -e "${RED}UDP_TIMEOUT${NC}"
        else
            echo "CHECK_SKIP(nc missing)"
        fi
    done
fi

echo -e "\n${YELLOW}=== [3. 协议层与管理通道审计] ===${NC}"
# 3.1 Chrony 深度诊断 (含 IPv4/IPv6 交叉检查)
if pgrep -x "chronyd" > /dev/null; then
    echo "--- Chrony Management Status ---"
    TRACKING_RES=$(chronyc tracking 2>&1)
    if [[ $TRACKING_RES == *"Cannot talk to daemon"* ]]; then
        echo -e "${RED}[FAIL] chronyc 无法连接服务端 (506)${NC}"
        echo "正在审计本地监听边界..."
        LSOF_RES=$(ss -unlp | grep :323)
        if [ -z "$LSOF_RES" ]; then
            echo -e "${RED}[CAUSE] 服务未监听管理端口 (323)${NC}"
        else
            echo "$LSOF_RES"
            echo -e "${YELLOW}[TIP] 检查 bindcmdaddress 是否排除了 127.0.0.1 或 [::1]${NC}"
        fi
    else
        echo "$TRACKING_RES"
    fi
fi

# 3.2 NTPD 诊断
if pgrep -x "ntpd" > /dev/null; then
    echo "--- NTPD Status ---"
    ntpq -p 2>&1 | grep -v "refused" || echo -e "${RED}[ERROR] ntpq 查询失败，请检查 restrict 策略${NC}"
fi

echo -e "\n${YELLOW}=== [4. 内核、硬件与虚拟化审计] ===${NC}"
# 4.1 内核时钟源
CUR_CS=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource 2>/dev/null)
echo "Clocksource: $CUR_CS"

# 4.2 虚拟化 Steal Time 检查
if grep -iq "hypervisor" /proc/cpuinfo; then
    echo -n "VM Detect: "
    vmstat 1 2 | tail -n 1 | awk '{if($16 > 0) print "RED ALERT: Steal Time "$16"%"; else print "Normal"}'
fi

echo -e "\n${YELLOW}=== [5. 系统日志实时分析] ===${NC}"
# 提取最近 20 行与时间相关的异常日志
if command -v journalctl &>/dev/null; then
    journalctl -u chronyd --since "1 hour ago" --no-pager | grep -Ei "panic|error|refused|step|jump" | tail -n 5
else
    grep -Ei "ntp|chrony" /var/log/messages 2>/dev/null | grep -Ei "error|panic|reject" | tail -n 5
fi

echo -e "\n${GREEN}诊断完成。报告已记录至: $LOG_FILE${NC}"