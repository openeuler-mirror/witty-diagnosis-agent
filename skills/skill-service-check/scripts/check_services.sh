#!/bin/bash

# 系统服务状态检查脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 帮助信息
show_help() {
    echo "系统服务状态检查脚本"
    echo "用法: $0 [服务名...]"
    echo "示例:"
    echo "  $0              # 检查所有关键服务"
    echo "  $0 sshd nginx   # 检查指定服务"
    echo "  $0 --help       # 显示帮助信息"
}

# 检查服务状态
check_service() {
    local service=$1
    if systemctl list-unit-files | grep -q "^${service}.service"; then
        local status=$(systemctl is-active $service 2>/dev/null)
        if [ "$status" = "active" ]; then
            echo -e "${GREEN}✓ $service: 运行中${NC}"
        else
            echo -e "${RED}✗ $service: $status${NC}"
        fi
    else
        echo -e "${YELLOW}? $service: 未安装${NC}"
    fi
}

# 默认检查的服务列表
DEFAULT_SERVICES=("sshd" "network" "docker" "nginx" "mysql" "postgresql")

# 主函数
main() {
    if [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi

    echo -e "${BLUE}=== 系统服务状态检查 ===${NC}"
    echo

    # 如果有参数，检查指定服务
    if [ $# -gt 0 ]; then
        for service in "$@"; do
            check_service $service
        done
    else
        # 检查默认服务列表
        for service in "${DEFAULT_SERVICES[@]}"; do
            check_service $service
        done
    fi

    echo
    echo -e "${BLUE}=== 检查完成 ===${NC}"
}

main "$@"