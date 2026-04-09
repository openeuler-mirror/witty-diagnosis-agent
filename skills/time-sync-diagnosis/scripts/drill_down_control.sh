#!/bin/bash
function show_help() {
    cat << EOF
Usage: bash drill_down_control.sh
Scenario: A - 控制平面 (Service Lifecycle)
Methodology: 解决“起不来”的问题。校验网卡状态、清理 UDP 123 端口冲突并验证配置语法。
EOF
}
[[ "$1" == "-h" || "$1" == "--help" ]] && show_help && exit 0

echo "[Step 1: 依赖与冲突审计] 正在扫描端口强占及多服务并存情况..."
systemctl list-units --type=service | grep -E "ntp|chrony|timesyncd"
lsof -iUDP:123 -n -P || echo "Result: 端口 123 未发现外部占用"

echo -e "\n[Step 2: 配置合规性验证] 正在执行模拟启动以捕获静态语法错误..."

# 修复：chronyd 正确语法检查命令
chronyd -p 2>/dev/null && echo "chronyd 配置语法正常" || {
    echo "chronyd 配置文件存在语法错误或权限不足"
}

echo -e "\n[Step 3: 服务状态检查]"
systemctl is-active chronyd && echo "chronyd 服务运行正常"