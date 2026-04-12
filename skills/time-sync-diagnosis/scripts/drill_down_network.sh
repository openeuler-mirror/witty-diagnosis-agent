#!/bin/bash

# =================================================================
# Script Name: drill_down_network.sh
# Scenario:    C - 链路通断 (通用自动化诊断版)
# =================================================================

echo "--- [NTP/Chrony Network Diagnostic Tool] ---"

# 1.1 定位配置文件
CHRONY_CONF="/etc/chrony/chrony.conf"
[ -f "/etc/chrony.conf" ] && CHRONY_CONF="/etc/chrony.conf"
echo "Checking Active Config: $CHRONY_CONF"

# 1.2 故障检测与目标自动选择
echo -e "\n[Step 1: 配置文件完整性检查]"
ACTIVE_SERVER=$(grep -E '^(server|pool)' "$CHRONY_CONF" | awk '{print $2}' | head -1)

if [ -z "$ACTIVE_SERVER" ]; then
    echo -e "\033[31m[DETECTED] 故障点：配置文件中没有任何激活的同步源！\033[0m"
    echo "脚本将自动从公共 NTP 池选择探测目标，验证网络是否正常..."
    
    # 按照优先级尝试不同的公共源进行探测
    CHECK_LIST=("ntp.aliyun.com" "pool.ntp.org" "cn.ntp.org.cn" "time.apple.com")
    SERVER=""
    for target in "${CHECK_LIST[@]}"; do
        if getent hosts "$target" > /dev/null; then
            SERVER="$target"
            break
        fi
    done
    [ -z "$SERVER" ] && SERVER="pool.ntp.org" # 最终兜底
    IS_CONFIG_FAULT=true
else
    echo -e "\033[32m[PASS]\033[0m 配置文件中已定义同步源。"
    SERVER="$ACTIVE_SERVER"
    IS_CONFIG_FAULT=false
fi

echo -e "Diagnostic Target: \033[36m$SERVER\033[0m"

# -----------------------------------------------------------------
# 2. 自动化链路探测
# -----------------------------------------------------------------
echo -e "\n[Step 2: 链路连通性深度剥离]"

# DNS 探测
if getent hosts "$SERVER" > /dev/null; then
    DNS_STATUS="OK"
    echo "Result: DNS 解析正常"
else
    DNS_STATUS="FAIL"
    echo "Result: DNS 解析失败"
fi

# UDP 123 探测
if nc -zu -w 3 "$SERVER" 123 2>/dev/null; then
    NET_STATUS="OK"
    echo "Result: UDP 123 端口通畅"
else
    NET_STATUS="FAIL"
    echo "Result: UDP 123 探测超时 (防火墙或链路封锁)"
fi

# -----------------------------------------------------------------
# 3. 自动化综合诊断结论
# -----------------------------------------------------------------
echo -e "\n[Step 3: 综合诊断报告]"

if [ "$IS_CONFIG_FAULT" = true ]; then
    if [ "$NET_STATUS" = "OK" ]; then
        echo -e "\033[31m>>> 最终结论：【配置文件故障】\033[0m"
        echo "证据：主配置文件无有效 server，但通过公共源 ($SERVER) 验证网络链路正常。"
    else
        echo -e "\033[31m>>> 最终结论：【双重复合故障 / 全面隔离】\033[0m"
        echo "证据：配置缺失且无法接通外部任何 NTP 公共源。"
    fi
else
    if [ "$NET_STATUS" = "OK" ]; then
        echo -e "\033[32m>>> 最终结论：【服务正常】\033[0m"
        echo "证据：配置存在且链路通畅。"
    else
        echo -e "\033[31m>>> 最终结论：【特定链路故障】\033[0m"
        echo "证据：配置正确，但无法连接到指定的服务器 $SERVER。"
    fi
fi

# 4. 路由追踪
echo -e "\n[Step 4: 路由路径分析 (MTR)]"
# 限制 MTR 发送包数量为 4 个，提高效率
mtr -u -P 123 -c 4 --report "$SERVER" 2>/dev/null || traceroute -U -p 123 "$SERVER" 2>/dev/null

echo -e "\n--- Diagnostic Complete ---"