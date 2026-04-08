#!/bin/bash

# openEuler系统信息速查脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助信息
show_help() {
    echo "openEuler系统信息速查脚本"
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  --help    显示此帮助信息"
    echo "  --all     显示所有系统信息"
    echo "  --basic   只显示基本系统信息"
    echo "  --hardware 只显示硬件信息"
    echo "  --network 只显示网络信息"
}

# 检查是否为openEuler系统
check_openeuler() {
    if [ -f "/etc/os-release" ]; then
        if grep -q "openEuler" /etc/os-release; then
            return 0
        else
            echo -e "${RED}错误: 此脚本仅适用于openEuler操作系统${NC}"
            return 1
        fi
    else
        echo -e "${RED}错误: 无法找到/etc/os-release文件${NC}"
        return 1
    fi
}

# 显示基本系统信息
show_basic_info() {
    echo -e "${BLUE}=== 基本系统信息 ===${NC}"
    
    # 操作系统版本
    echo -e "${GREEN}操作系统版本:${NC}"
    if [ -f "/etc/os-release" ]; then
        cat /etc/os-release | grep -E "NAME|VERSION"
    else
        echo -e "${YELLOW}无法获取操作系统版本信息${NC}"
    fi
    
    # 内核版本
    echo -e "${GREEN}内核版本:${NC}"
    if command -v uname &> /dev/null; then
        uname -r
    else
        echo -e "${YELLOW}无法获取内核版本信息${NC}"
    fi
    
    # 系统架构
    echo -e "${GREEN}系统架构:${NC}"
    if command -v uname &> /dev/null; then
        uname -m
    else
        echo -e "${YELLOW}无法获取系统架构信息${NC}"
    fi
    
    # 主机名
    echo -e "${GREEN}主机名:${NC}"
    if command -v hostname &> /dev/null; then
        hostname
    else
        echo -e "${YELLOW}无法获取主机名信息${NC}"
    fi
    
    echo
}

# 显示硬件信息
show_hardware_info() {
    echo -e "${BLUE}=== 硬件信息 ===${NC}"
    
    # CPU信息
    echo -e "${GREEN}CPU信息:${NC}"
    if command -v lscpu &> /dev/null; then
        lscpu | grep -E "Model name|CPU(s):|Thread(s) per core|Core(s) per socket|Socket(s):"
    elif command -v cat &> /dev/null && [ -f "/proc/cpuinfo" ]; then
        cat /proc/cpuinfo | grep -E "model name|cpu cores" | head -n 5
    else
        echo -e "${YELLOW}无法获取CPU信息${NC}"
    fi
    
    # 内存信息
    echo -e "${GREEN}内存信息:${NC}"
    if command -v free &> /dev/null; then
        free -h
    elif command -v cat &> /dev/null && [ -f "/proc/meminfo" ]; then
        cat /proc/meminfo | grep -E "MemTotal|MemFree" | head -n 2
    else
        echo -e "${YELLOW}无法获取内存信息${NC}"
    fi
    
    # 磁盘信息
    echo -e "${GREEN}磁盘使用情况:${NC}"
    if command -v df &> /dev/null; then
        df -h | grep -v tmpfs
    else
        echo -e "${YELLOW}无法获取磁盘信息${NC}"
    fi
    
    echo
}

# 显示网络信息
show_network_info() {
    echo -e "${BLUE}=== 网络信息 ===${NC}"
    
    # IP地址信息
    echo -e "${GREEN}IP地址信息:${NC}"
    if command -v ip &> /dev/null; then
        ip addr | grep -E "inet "
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "inet "
    else
        echo -e "${YELLOW}无法获取IP地址信息${NC}"
    fi
    
    # 网络接口状态
    echo -e "${GREEN}网络接口状态:${NC}"
    if command -v ip &> /dev/null; then
        ip link | grep -E "state "
    elif command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "UP|DOWN" | head -n 5
    else
        echo -e "${YELLOW}无法获取网络接口状态${NC}"
    fi
    
    echo
}

# 主函数
main() {
    # 检查是否为openEuler系统
    check_openeuler || exit 1
    
    # 处理命令行参数
    case "$1" in
        --help)
            show_help
            ;;
        --basic)
            show_basic_info
            ;;
        --hardware)
            show_hardware_info
            ;;
        --network)
            show_network_info
            ;;
        --all | *)
            show_basic_info
            show_hardware_info
            show_network_info
            ;;
    esac
    
    echo -e "${BLUE}=== 系统信息检查完成 ===${NC}"
}

# 执行主函数
main "$@"