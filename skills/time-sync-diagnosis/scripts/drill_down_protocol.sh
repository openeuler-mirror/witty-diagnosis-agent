#!/bin/bash
function show_help() {
    cat << EOF
Usage: bash drill_down_protocol.sh
Scenario: E - 协议逻辑 (Protocol Logic)
Methodology: 解决“不信”的问题。重置 Panic 挂起状态，强制步进同步并识别离群同步源。
EOF
}
[[ "$1" == "-h" || "$1" == "--help" ]] && show_help && exit 0

echo "[Step 1: 协议一致性审计] 正在检查同步源置信度..."
chronyc sources -v 2>/dev/null | grep -E "^\*|^\+|^\-|^x|^\?" | grep -q "x"
if [ $? -eq 0 ]; then
    echo "Alert: 发现不可信的时间源 (x)"
else
    echo "Result: 所有同步源均可信"
fi

echo -e "\n[Step 2: 强制纠偏动作] 正在执行 Burst 突发采样与强制步进..."
if command -v chronyc &>/dev/null; then
    chronyc burst 4/4 2>/dev/null
    sleep 1
    chronyc makestep 2>/dev/null
    echo "Result: 强制时间纠偏完成 (burst + makestep)"
else
    echo "Result: chronyc 不存在，使用 ntpq 检查偏移"
    ntpq -c rv 2>/dev/null | grep -Ei "dispersion|jitter"
fi

echo -e "\n[Protocol Logic 诊断完成]"