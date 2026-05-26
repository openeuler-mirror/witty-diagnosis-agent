#!/bin/bash

# =================================================================
# Script Name: drill_down_mgmt.sh
# Scenario:    B - 管理通道 (ACL & Interface)
# Methodology: 解决“管不了”的问题。校验绑定状态及访问控制策略。
# =================================================================

function show_help() {
    cat << EOF
Usage: bash drill_down_mgmt.sh
Scenario: B - 管理通道 (ACL & Interface)
Methodology: 校验 127.0.0.1 绑定状态及访问控制策略。
EOF
}

[[ "$1" == "-h" || "$1" == "--help" ]] && show_help && exit 0

echo "--- [NTP/Chrony Management Channel Audit] ---"

# --- Step 1: 动态定位配置文件路径 ---
CHRONY_CONF="/etc/chrony/chrony.conf"
# 优先从运行进程中抓取路径
if pgrep -x "chronyd" > /dev/null; then
    PROC_CONF=$(ps -ef | grep "[c]hronyd" | sed -n 's/.*-f \([^ ]*\).*/\1/p')
    [ -n "$PROC_CONF" ] && CHRONY_CONF="$PROC_CONF"
else
    # 进程不在时，探测常见默认路径
    for path in "/etc/chrony/chrony.conf" "/etc/chrony.conf"; do
        [ -f "$path" ] && CHRONY_CONF="$path" && break
    done
fi

echo "Using Config: $CHRONY_CONF"

# --- Step 2: 监听边界审计 ---
echo -e "\n[Step 1: 监听边界审计] 正在检查服务是否监听了回环地址..."
# 检查 UDP 123 (NTP) 和 UDP 323 (Chrony 管理端口)
LISTEN_STATUS=$(ss -unlp | grep -E ":123|:323")

if echo "$LISTEN_STATUS" | grep -E "127.0.0.1|::1|0.0.0.0|\[::\]" > /dev/null; then
    echo -e "Result: \033[32mPASS\033[0m (服务已绑定回环或全网地址)"
    echo "$LISTEN_STATUS" | awk '{print $1, $4, $5, $6}'
else
    echo -e "Result: \033[31mALERT\033[0m (服务未监听回环地址，管理工具将无法连接)"
fi

# --- Step 3: ACL 策略审计 ---
echo -e "\n[Step 2: 访问控制(ACL)策略审计]"
if [ -f "$CHRONY_CONF" ]; then
    # 检索关键的准入指令：
    # - bindcmdaddress: 管理指令监听地址
    # - cmdallow: 允许哪些地址执行管理指令
    # - allow: 允许哪些地址同步时间
    ACL_RULES=$(grep -E "^(bindcmdaddress|cmdallow|allow|bindaddress|restrict)" "$CHRONY_CONF")
    
    if [ -n "$ACL_RULES" ]; then
        echo "发现如下 ACL/绑定配置："
        echo -e "\033[33m$ACL_RULES\033[0m"
        
        # 特殊逻辑：检查是否禁用了 localhost
        if echo "$ACL_RULES" | grep -q "cmdallow"; then
            if ! echo "$ACL_RULES" | grep -Eq "cmdallow (127.0.0.1|localhost|::1)"; then
                echo -e "\033[31mWarning: 存在 cmdallow 限制，但未明确允许 127.0.0.1，这可能导致本地查询失败。\033[0m"
            fi
        fi
    else
        echo "Notice: 配置文件中未发现显式 ACL 限制，通常代表使用系统默认权限。"
    fi
else
    echo "Error: 无法读取配置文件，跳过 ACL 审计。"
fi

echo -e "\n--- Audit Complete ---"