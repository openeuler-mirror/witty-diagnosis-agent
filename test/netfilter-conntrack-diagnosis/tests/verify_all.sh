#!/usr/bin/env bash
# =============================================================================
# 统一验证脚本
# 用途: 对已注入的故障运行诊断脚本，检验 skill 各分支的诊断能力
# 验证流程:
#   1. 检查每个故障注入容器是否存在
#   2. 在容器内执行 01_collect_baseline.sh 基线采集
#   3. 执行对应分支的诊断脚本
#   4. 判断诊断结果是否与注入故障匹配
# =============================================================================
# 使用:
#   bash verify_all.sh                 # 验证所有已注入的故障
#   bash verify_all.sh --list          # 列出可验证的故障
#   bash verify_all.sh --only A        # 只验证特定分支 (A-H)
#   bash verify_all.sh --summary       # 只查看汇总结果
#   bash verify_all.sh --container <容器名> <分支名>  # 验证特定容器
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 测试结果汇总
TEST_RESULTS=()
TEST_PASS=0
TEST_FAIL=0
TEST_SKIP=0

# =============================================================================
# 定义每个分支的容器名和诊断脚本映射
# =============================================================================
declare -A BRANCH_CONTAINER_MAP
BRANCH_CONTAINER_MAP["A"]="netfilter-fault-conntrack_full"
BRANCH_CONTAINER_MAP["B"]="netfilter-fault-rule_mishit"
BRANCH_CONTAINER_MAP["C"]="netfilter-fault-nat_mapping"
BRANCH_CONTAINER_MAP["D"]="netfilter-fault-ct_state_drop"
BRANCH_CONTAINER_MAP["E"]="netfilter-fault-tcp_window"
BRANCH_CONTAINER_MAP["F"]="netfilter-fault-ct_timeout"
BRANCH_CONTAINER_MAP["G"]="netfilter-fault-helper_alg"
BRANCH_CONTAINER_MAP["H"]="netfilter-fault-ipset"

declare -A BRANCH_SCRIPT_MAP
BRANCH_SCRIPT_MAP["A"]="branch_A_conntrack_full.sh"
BRANCH_SCRIPT_MAP["B"]="branch_B_rule_mishit.sh"
BRANCH_SCRIPT_MAP["C"]="branch_C_nat_mapping.sh"
BRANCH_SCRIPT_MAP["D"]="branch_D_ct_state_drop.sh"
BRANCH_SCRIPT_MAP["E"]="branch_E_tcp_window.sh"
BRANCH_SCRIPT_MAP["F"]="branch_F_ct_timeout.sh"
BRANCH_SCRIPT_MAP["G"]="branch_G_helper_alg.sh"
BRANCH_SCRIPT_MAP["H"]="branch_H_ipset.sh"

declare -A BRANCH_NAME_MAP
BRANCH_NAME_MAP["A"]="nf_conntrack 表满溢出"
BRANCH_NAME_MAP["B"]="规则误命中 DROP/REJECT"
BRANCH_NAME_MAP["C"]="NAT/SNAT/DNAT 映射异常"
BRANCH_NAME_MAP["D"]="conntrack 状态丢包 (INVALID/UNREPLIED)"
BRANCH_NAME_MAP["E"]="TCP window tracking 异常"
BRANCH_NAME_MAP["F"]="conntrack timeout 超时"
BRANCH_NAME_MAP["G"]="helper/ALG 协议辅助模块故障"
BRANCH_NAME_MAP["H"]="ipset 匹配失效"

declare -A BRANCH_KEYWORD_MAP
BRANCH_KEYWORD_MAP["A"]="table full"
BRANCH_KEYWORD_MAP["B"]="DROP"
BRANCH_KEYWORD_MAP["C"]="DNAT"
BRANCH_KEYWORD_MAP["D"]="INVALID"
BRANCH_KEYWORD_MAP["E"]="invalid"
BRANCH_KEYWORD_MAP["F"]="timeout"
BRANCH_KEYWORD_MAP["G"]="helper"
BRANCH_KEYWORD_MAP["H"]="ipset"

# =============================================================================
# 验证单个分支
# =============================================================================
verify_branch() {
    local branch_id="$1"
    local container_name="${BRANCH_CONTAINER_MAP[${branch_id}]}"
    local branch_script="${BRANCH_SCRIPT_MAP[${branch_id}]}"
    local branch_name="${BRANCH_NAME_MAP[${branch_id}]}"
    local keyword="${BRANCH_KEYWORD_MAP[${branch_id}]}"

    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
    echo -e "${CYAN}  分支 ${branch_id}: ${branch_name}${NC}"
    echo -e "${CYAN}  容器: ${container_name}${NC}"
    echo -e "${CYAN}  诊断脚本: ${branch_script}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"

    # 检查容器是否存在
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container_name}$"; then
        echo -e "  ${YELLOW}⚠ 容器 ${container_name} 未运行，跳过验证${NC}"
        echo -e "  ${YELLOW}  请先运行对应的故障注入脚本:${NC}"
        echo -e "  ${YELLOW}    bash inject/inject_fault_${branch_id}_*.sh${NC}"
        echo ""
        TEST_RESULTS+=("${branch_id}|SKIP|${branch_name}|容器未运行")
        ((TEST_SKIP++))
        return
    fi

    # ---- 阶段1: 运行基线采集 ----
    echo -e "\n  ${BLUE}[阶段1]${NC} 运行基线采集..."
    local base_output
    base_output=$(docker exec "${container_name}" bash /scripts/01_collect_baseline.sh --out /tmp/netfilter_diag_verify 2>&1 || true)

    # 提取输出目录
    local base_dir="/tmp/netfilter_diag_verify"
    if echo "${base_output}" | grep -q "输出目录"; then
        base_dir=$(echo "${base_output}" | grep "输出目录" | head -1 | grep -oP '/tmp/netfilter_diag_\S+' || echo "/tmp/netfilter_diag_verify")
    fi
    echo -e "  ${GREEN}基线采集完成，输出目录: ${base_dir}${NC}"

    # ---- 阶段2: 运行分支诊断 ----
    echo -e "\n  ${BLUE}[阶段2]${NC} 运行分支诊断: ${branch_script}..."
    local diag_output
    diag_output=$(docker exec "${container_name}" bash "/scripts/${branch_script}" "${base_dir}" 2>&1 || true)

    # 显示诊断摘要（前30行）
    echo -e "  ${CYAN}诊断输出摘要:${NC}"
    echo "${diag_output}" | head -30 | sed 's/^/    /'

    # ---- 阶段3: 验证诊断结果 ----
    echo -e "\n  ${BLUE}[阶段3]${NC} 验证诊断是否检测到注入故障..."

    local match_result=""
    local detected=false

    # 检查诊断输出中是否包含预期关键字
    if echo "${diag_output}" | grep -qi "${keyword}"; then
        detected=true
        match_result="${GREEN}✅ 匹配${NC}"
        echo -e "  ${GREEN}✅ 诊断成功检测到关键字 '${keyword}'${NC}"
        TEST_RESULTS+=("${branch_id}|PASS|${branch_name}|关键字 '${keyword}' 被检测到")
        ((TEST_PASS++))
    else
        # 尝试在输出中查找其他相关关键字
        local fallback_keywords=("conntrack" "iptables" "ipset" "NAT" "DROP" "REJECT" "timeout" "invalid" "helper")
        local found_any=false
        for fk in "${fallback_keywords[@]}"; do
            if echo "${diag_output}" | grep -qi "${fk}"; then
                found_any=true
                break
            fi
        done

        if ${found_any}; then
            match_result="${YELLOW}⚠ 部分匹配${NC}"
            echo -e "  ${YELLOW}⚠ 未直接检测到关键字 '${keyword}'，但诊断输出了 netfilter 相关信息${NC}"
            TEST_RESULTS+=("${branch_id}|PARTIAL|${branch_name}|关键字 '${keyword}' 未直接命中")
            ((TEST_FAIL++))
        else
            match_result="${RED}❌ 不匹配${NC}"
            echo -e "  ${RED}❌ 诊断未能检测到注入的故障 (关键字: '${keyword}')${NC}"
            TEST_RESULTS+=("${branch_id}|FAIL|${branch_name}|未检测到故障")
            ((TEST_FAIL++))
        fi
    fi

    # 输出诊断详情（完整输出保存到文件）
    local log_file="/tmp/netfilter_verify_${branch_id}_$(date +%Y%m%d%H%M%S).log"
    echo "${diag_output}" > "${log_file}"
    echo -e "\n  ${CYAN}完整诊断日志: ${log_file}${NC}"
    echo ""
}

# =============================================================================
# 显示汇总结果
# =============================================================================
show_summary() {
    echo ""
    echo -e "${BLUE}================================================================"
    echo "  验证汇总结果"
    echo -e "================================================================${NC}"
    echo ""

    printf "  %-8s %-12s %-45s %s\n" "分支" "结果" "故障类型" "说明"
    printf "  %-8s %-12s %-45s %s\n" "────" "────" "────────────────────────" "────"

    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r branch status name detail <<< "${result}"
        case "${status}" in
            PASS)    status_display="${GREEN}PASS${NC}       " ;;
            PARTIAL) status_display="${YELLOW}PARTIAL${NC}     " ;;
            FAIL)    status_display="${RED}FAIL${NC}       " ;;
            SKIP)    status_display="${CYAN}SKIP${NC}       " ;;
        esac
        printf "  %-8s %b %-15s %s\n" "${branch}" "${status_display}" "${name}" "${detail}"
    done

    echo ""
    echo -e "  ${GREEN}通过: ${TEST_PASS}${NC}  |  ${YELLOW}部分: $((TEST_FAIL - $(echo "${TEST_RESULTS[@]}" | tr ' ' '\n' | grep 'PARTIAL' | wc -l)))${NC}  |  ${RED}失败: ${TEST_FAIL}${NC}  |  ${CYAN}跳过: ${TEST_SKIP}${NC}"
    echo ""

    local total=$((TEST_PASS + TEST_FAIL + TEST_SKIP))
    local pass_rate=0
    if [[ ${total} -gt 0 && $((total - TEST_SKIP)) -gt 0 ]]; then
        pass_rate=$((TEST_PASS * 100 / (total - TEST_SKIP)))
    fi
    echo -e "  诊断覆盖率: ${pass_rate}% (${TEST_PASS}/$((total - TEST_SKIP))) 的故障被诊断脚本成功检测"
    echo ""

    # 生成机器可读的 JSON 结果
    local json_file="/tmp/netfilter_verify_results_$(date +%Y%m%d%H%M%S).json"
    {
        echo "{"
        echo "  \"verify_time\": \"$(date -Iseconds)\","
        echo "  \"results\": ["
        local first=true
        for result in "${TEST_RESULTS[@]}"; do
            IFS='|' read -r branch status name detail <<< "${result}"
            ${first} || echo ","
            first=false
            echo -n "    {\"branch\": \"${branch}\", \"status\": \"${status}\", \"name\": \"${name}\", \"detail\": \"${detail}\"}"
        done
        echo ""
        echo "  ],"
        echo "  \"summary\": {"
        echo "    \"pass\": ${TEST_PASS},"
        echo "    \"fail\": ${TEST_FAIL},"
        echo "    \"skip\": ${TEST_SKIP}"
        echo "  }"
        echo "}"
    } > "${json_file}"
    echo -e "  ${CYAN}JSON 结果文件: ${json_file}${NC}"
    echo ""
}

# =============================================================================
# 主流程
# =============================================================================
main() {
    print_banner "Netfilter/conntrack 故障诊断验证"

    # 检查 Docker
    if ! docker ps &>/dev/null; then
        log_error "Docker 不可用，请确保 Docker 已安装并运行"
        exit 1
    fi

    local only_branch=""
    local show_only_summary=false
    local list_only=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --only)
                only_branch="$2"
                shift 2
                ;;
            --summary)
                show_only_summary=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            --container)
                # 验证特定容器: --container <容器名> <分支名>
                local custom_container="$2"
                local custom_branch="${3:-X}"
                shift 3
                verify_branch_custom "${custom_container}" "${custom_branch}"
                show_summary
                exit 0
                ;;
            *)
                echo "未知选项: $1"
                echo "使用: bash verify_all.sh [--only A|B|...] [--summary] [--list]"
                exit 1
                ;;
        esac
    done

    # 列出可验证的故障
    if [[ "${list_only}" == true ]]; then
        echo "可验证的故障分支:"
        for branch_id in A B C D E F G H; do
            local container="${BRANCH_CONTAINER_MAP[${branch_id}]}"
            local status
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
                status="${GREEN}[运行中]${NC}"
            else
                status="${YELLOW}[未启动]${NC}"
            fi
            echo -e "  ${branch_id}: ${BRANCH_NAME_MAP[${branch_id}]} ${status}"
            echo -e "         诊断脚本: ${BRANCH_SCRIPT_MAP[${branch_id}]}"
            echo -e "         容器: ${container}"
            echo ""
        done
        exit 0
    fi

    # 如果只查看汇总，但还没有结果文件
    if [[ "${show_only_summary}" == true ]]; then
        # 尝试从最近的结果文件加载
        local latest_json
        latest_json=$(ls -t /tmp/netfilter_verify_results_*.json 2>/dev/null | head -1)
        if [[ -n "${latest_json}" ]]; then
            echo -e "  ${CYAN}从已有结果文件加载: ${latest_json}${NC}"
            python3 -c "
import json
d = json.load(open('${latest_json}'))
print(f'  验证时间: {d[\"verify_time\"]}')
print(f'  通过: {d[\"summary\"][\"pass\"]}  失败: {d[\"summary\"][\"fail\"]}  跳过: {d[\"summary\"][\"skip\"]}')
for r in d['results']:
    print(f'  分支 {r[\"branch\"]}: {r[\"status\"]} - {r[\"name\"]}')
" 2>/dev/null || echo -e "  ${RED}无法解析结果文件${NC}"
        else
            echo -e "  ${YELLOW}无已有结果，请先运行 verify_all.sh${NC}"
        fi
        exit 0
    fi

    # 遍历所有分支
    for branch_id in A B C D E F G H; do
        if [[ -n "${only_branch}" && "${branch_id}" != "${only_branch}" ]]; then
            continue
        fi
        verify_branch "${branch_id}"
    done

    # 显示汇总
    show_summary

    # 最终结论
    echo ""
    if [[ ${TEST_FAIL} -eq 0 && ${TEST_PASS} -gt 0 ]]; then
        echo -e "${GREEN}🎉 所有诊断脚本均成功检测到注入的故障！${NC}"
    elif [[ ${TEST_PASS} -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 部分诊断脚本未完全检测到注入故障。请检查失败分支的诊断输出日志。${NC}"
    else
        echo -e "${RED}❌ 无诊断脚本成功检测到故障。请检查注入脚本和诊断脚本的兼容性。${NC}"
    fi
    echo ""
}

# 验证自定义容器的辅助函数
verify_branch_custom() {
    local container="$1"
    local branch="$2"

    if docker exec "${container}" true 2>/dev/null; then
        echo -e "${CYAN}验证自定义容器: ${container} 分支: ${branch}${NC}"
        local output
        output=$(docker exec "${container}" bash /scripts/01_collect_baseline.sh 2>&1 || true)
        echo "${output}" | tail -20
        TEST_RESULTS+=("${branch}|CUSTOM|${container}|自定义验证")
        ((TEST_PASS++))
    else
        TEST_RESULTS+=("${branch}|SKIP|${container}|容器不可用")
        ((TEST_SKIP++))
    fi
}

main "$@"
