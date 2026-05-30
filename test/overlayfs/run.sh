#!/usr/bin/env bash
# =============================================================================
# 脚本：run.sh
# 用途：OverlayFS 故障注入测试套件 —— 主入口
# 说明：提供交互式菜单和一键执行两种模式，用于在隔离容器中注入
#       OverlayFS 各类故障并执行诊断验证。
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

# ─────────────────────────────────────────────────────────────────────────────
# 可用故障分支列表
# ─────────────────────────────────────────────────────────────────────────────
declare -A BRANCHES
BRANCHES=(
    ["A"]="配置错误 - upper/lower/work 目录配置异常"
    ["B"]="文件系统不兼容 - upperdir 在不支持的 FS 上"
    ["C"]="跨设备 overlay - upper/work 在不同设备"
    ["D"]="Opaque Whiteout - 文件\"消失\"问题"
    ["E"]="Copy-up 性能退化 - 首次写入延迟高"
    ["F"]="inotify 失效 - merged 层无事件"
    ["G"]="inode 耗尽 - no space left 但 df 有余量"
    ["H"]="diff 目录膨胀 - overlay2 持续增长"
    ["I"]="redirect/metacopy 冲突"
    ["J"]="权限/元数据异常 - 写入报只读"
    ["K"]="readdir 性能 - 目录遍历缓慢"
    ["Z"]="通用故障 - 最小化复现环境"
)

# ─────────────────────────────────────────────────────────────────────────────
# 显示菜单
# ─────────────────────────────────────────────────────────────────────────────

show_menu() {
    header "OverlayFS 故障注入测试套件"
    echo "宿主机内核: $(uname -r)"
    echo ""
    echo "可用故障分支:"
    echo ""
    for key in A B C D E F G H I J K Z; do
        printf "  %s) %s\n" "${key}" "${BRANCHES[${key}]}"
    done
    echo ""
    echo "  all) 执行全部故障注入测试"
    echo "  clean) 清理所有测试容器"
    echo "  report) 生成测试报告"
    echo "  q) 退出"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# 分支执行器
# ─────────────────────────────────────────────────────────────────────────────

run_branch() {
    local branch="$1"
    declare -A MAP
    MAP[A]="config_error"; MAP[B]="fs_incompatible"; MAP[C]="cross_device"
    MAP[D]="opaque_whiteout"; MAP[E]="copyup_perf"; MAP[F]="inotify"
    MAP[G]="inode_exhaust"; MAP[H]="diff_bloat"; MAP[I]="redirect_metacopy"
    MAP[J]="permission"; MAP[K]="readdir_perf"; MAP[Z]="general"
    local name="${MAP[$branch]:-$branch}"
    local script="${SCRIPT_DIR}/fault_injection/branch_${branch}_${name}_inject.sh"

    if [[ ! -f "${script}" ]]; then
        error "未找到分支 ${branch} 的注入脚本: ${script}"
        return 1
    fi

    header "执行分支 ${branch}: ${BRANCHES[${branch}]:-未知}"
    bash "${script}"
    local ret=$?

    if [[ ${ret} -eq 0 ]]; then
        info "分支 ${branch} 注入完成"
    else
        error "分支 ${branch} 注入失败 (exit=${ret})"
    fi
    echo ""
    return ${ret}
}

# ─────────────────────────────────────────────────────────────────────────────
# 一键全执行
# ─────────────────────────────────────────────────────────────────────────────

run_all() {
    header "开始执行全部故障注入测试"
    mkdir -p "${OUTPUT_DIR}"
    > "${OUTPUT_DIR}/results.log"

    for key in A B C D E F G H I J K Z; do
        if [[ -f "${SCRIPT_DIR}/branch_${key}_inject.sh" ]]; then
            run_branch "${key}" || true
        else
            warn "跳过分支 ${key}: 注入脚本不存在"
        fi
    done

    info "全部故障注入测试执行完毕"
    generate_report
}

# ─────────────────────────────────────────────────────────────────────────────
# 清理所有
# ─────────────────────────────────────────────────────────────────────────────

clean_all() {
    header "清理所有测试容器和资源"

    for key in A B C D E F G H I J K Z; do
        local name="${CONTAINER_PREFIX}-${key}"
        if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
            info "清理容器: ${name}"
            docker rm -f "${name}" >/dev/null 2>&1 || true
        fi
    done

    # 可选：删除基础镜像
    read -r -p "是否删除基础镜像 overlayfs-fault-base:latest？(y/N) " confirm
    if [[ "${confirm}" == "y" || "${confirm}" == "Y" ]]; then
        docker rmi overlayfs-fault-base:latest >/dev/null 2>&1 || true
        info "基础镜像已删除"
    fi

    # 清理本地临时目录
    if [[ -d "${OUTPUT_DIR}" ]]; then
        rm -rf "${OUTPUT_DIR}"
        info "测试输出目录已清理: ${OUTPUT_DIR}"
    fi

    info "全部清理完成"
}

# ─────────────────────────────────────────────────────────────────────────────
# 主循环
# ─────────────────────────────────────────────────────────────────────────────

main() {
    # 检查依赖（一次性）
    check_dependencies

    # 支持命令行参数模式
    if [[ $# -ge 1 ]]; then
        case "$1" in
            all)
                run_all
                exit 0
                ;;
            clean)
                clean_all
                exit 0
                ;;
            report)
                if [[ -f "${OUTPUT_DIR}/results.log" ]]; then
                    generate_report
                else
                    error "尚无测试结果，请先执行 run.sh all 或 run.sh <分支字母>"
                fi
                exit 0
                ;;
            [A-Z])
                run_branch "$1"
                exit $?
                ;;
            *)
                echo "用法: $0 [all|clean|report|A|B|C|...|Z]"
                exit 1
                ;;
        esac
    fi

    # 交互模式
    while true; do
        show_menu
        read -r -p "请选择 [A/B/C/D/E/F/G/H/I/J/K/Z/all/clean/report/q]: " choice

        case "${choice,,}" in
            q|quit|exit)
                info "退出"
                exit 0
                ;;
            all)
                run_all
                ;;
            clean)
                clean_all
                ;;
            report)
                if [[ -f "${OUTPUT_DIR}/results.log" ]]; then
                    generate_report
                else
                    warn "尚无测试结果"
                fi
                ;;
            a|b|c|d|e|f|g|h|i|j|k|z)
                run_branch "${choice^^}"
                ;;
            *)
                warn "无效选择: ${choice}"
                ;;
        esac

        echo ""
        read -r -p "按 Enter 继续..."
    done
}

main "$@"
