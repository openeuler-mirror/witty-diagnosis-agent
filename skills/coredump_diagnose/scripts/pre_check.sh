#!/bin/bash
# ==============================================================================
# 前置环境检查 + 二进制自动发现
# 功能：
#   1. 检查 gdb 可用
#   2. 检查 core 文件有效
#   3. 自动从 core 头信息提取崩溃程序路径
#   4. 最后输出 CORE 和 BINARY 绝对路径，方便后续步骤直接使用
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

CORE_FILE=""
BINARY_FILE=""
AUTO_FOUND_BIN_CACHE="/tmp/.coredump_auto_bin.tmp"

show_help() {
    cat << EOF
用法：
    ./00_pre_check.sh --core <core文件> [--binary <崩溃程序>]

功能：
    前置环境检查 + 崩溃程序自动发现
    若不传入 --binary，脚本会自动从 core 文件中提取

参数：
    -c, --core FILE      必填：coredump 文件路径
    -b, --binary FILE    可选：崩溃的二进制程序路径
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--core) CORE_FILE="$2"; shift 2 ;;
            -b|--binary) BINARY_FILE="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) echo -e "${RED}未知参数：$1${NC}"; show_help; exit 1 ;;
        esac
    done

    if [[ -z "$CORE_FILE" ]]; then
        echo -e "${RED}错误：必须传入 --core${NC}"
        show_help
        exit 1
    fi
}

# 检查 GDB
check_gdb() {
    echo -n "[1/4] 检查 GDB 是否安装..."
    if command -v gdb &>/dev/null; then
        echo -e " ${GREEN}OK${NC}"
    else
        echo -e " ${RED}失败${NC}"
        echo -e "${RED}请先安装 gdb：yum install gdb 或 apt install gdb${NC}"
        exit 1
    fi
}

# 检查 Core 文件
check_core() {
    echo -n "[2/4] 检查 Core 文件..."
    if [[ ! -f "$CORE_FILE" ]]; then
        echo -e " ${RED}不存在${NC}"
        exit 1
    fi
    if [[ ! -r "$CORE_FILE" ]]; then
        echo -e " ${RED}不可读${NC}"
        exit 1
    fi
    echo -e " ${GREEN}OK${NC}"
}

# 从 file(1) 对 ELF core 的典型输出中解析可执行文件路径（不依赖 grep -P）
# 新版 file 会带 execfn: '/绝对路径/解释器'；from 可能仅为 'python3' 等 basename，需优先 execfn
parse_exe_path_from_file_core_out() {
    local raw="$1"
    local execfn from_field

    execfn=$(echo "$raw" | sed -n "s/.*execfn: '\\([^']*\\)'.*/\1/p" | head -n 1 | tr -d '\r')
    if [[ -n "$execfn" && -f "$execfn" && -r "$execfn" ]]; then
        echo "$execfn"
        return 0
    fi

    from_field=$(echo "$raw" | sed -n "s/.*[Ff]rom '\\([^']*\\)'.*/\1/p" | head -n 1 | tr -d '\r')
    if [[ -n "$from_field" && "$from_field" == /* && -f "$from_field" && -r "$from_field" ]]; then
        echo "$from_field"
        return 0
    fi

    if [[ -n "$from_field" && "$from_field" != /* ]]; then
        if command -v "$from_field" &>/dev/null; then
            command -v "$from_field"
            return 0
        fi
    fi

    [[ -n "$from_field" ]] && echo "$from_field"
    return 1
}

# 尝试用 readelf 从 PT_NOTE 快速取路径（不扫全文件，通常比 file 大 core 更稳）
guess_exe_from_readelf() {
    command -v readelf &>/dev/null || return 1
    # NT_FILE / 部分内核会带可执行路径描述；不同发行版格式略有差异，取首条绝对路径
    readelf -n "$CORE_FILE" 2>/dev/null \
        | grep -oE '/[A-Za-z0-9._/+-]+(bin/[^ ]+|/python[^ ]*)' \
        | head -n 1
}

# 自动发现 Binary
autodetect_binary() {
    echo -n "[3/4] 自动发现二进制程序..."

    rm -f "$AUTO_FOUND_BIN_CACHE"

    # 如果用户已经传了，直接用
    if [[ -n "$BINARY_FILE" ]]; then
        if [[ -f "$BINARY_FILE" && -r "$BINARY_FILE" ]]; then
            echo -e " ${GREEN}用户指定${NC}"
            echo "$BINARY_FILE" > "$AUTO_FOUND_BIN_CACHE"
            return
        else
            echo -e " ${RED}用户指定的二进制无效${NC}"
            exit 1
        fi
    fi

    local guessed=""
    local core_size
    core_size=$(stat -c%s "$CORE_FILE" 2>/dev/null || stat -f%z "$CORE_FILE" 2>/dev/null || echo 0)
    # 大 core 时 file(1) 可能长时间读盘，先提示避免误以为死机
    if [[ "${core_size:-0}" -gt $((256 * 1024 * 1024)) ]]; then
        echo ""
        echo -e "${YELLOW}    Core 较大（约 $((core_size / 1024 / 1024)) MiB），解析可能需数十秒…${NC}"
    fi

    # 1) 优先 readelf（只读 ELF 头附近 note，通常更快）
    guessed=$(guess_exe_from_readelf || true)
    guessed=$(echo "$guessed" | awk '{print $1}' | head -n 1)

    # 2) 再尝试 file；大文件时对 file 加超时（需 coreutils timeout）
    if [[ -z "$guessed" || ! -f "$guessed" ]]; then
        guessed=""
        if command -v file &>/dev/null; then
            local file_out=""
            if command -v timeout &>/dev/null; then
                file_out=$(timeout 120 file "$CORE_FILE" 2>/dev/null) || file_out=""
            else
                file_out=$(file "$CORE_FILE" 2>/dev/null) || file_out=""
            fi
            guessed=$(parse_exe_path_from_file_core_out "$file_out") || true
            guessed=$(echo "$guessed" | awk '{print $1}' | head -n 1 | tr -d '"')
        fi
    fi

    if [[ -n "$guessed" && -f "$guessed" && -r "$guessed" ]]; then
        echo -e " ${GREEN}自动发现成功${NC}"
        echo "$guessed" > "$AUTO_FOUND_BIN_CACHE"
        return
    fi

    echo -e " ${YELLOW}无法自动发现二进制文件${NC}"
    echo ""
    echo -e "${RED}请手动指定：--binary /path/to/崩溃程序${NC}"
    exit 1
}

# 检查调试信息
check_debug_info() {
    echo -n "[4/4] 检查调试信息..."
    local bin
    bin=$(cat "$AUTO_FOUND_BIN_CACHE")

    if command -v objdump &>/dev/null && objdump -h "$bin" | grep -q .debug_line; then
        echo -e " ${GREEN}已包含 (-g)${NC}"
    else
        echo -e " ${YELLOW}无调试信息，缺少行号${NC}"
    fi
}

# 最终输出：路径（给后续步骤用）
print_final_paths() {
    local core_abs
    core_abs=$(realpath "$CORE_FILE")
    
    local bin_abs
    bin_abs=$(realpath "$(cat "$AUTO_FOUND_BIN_CACHE")")

    echo ""
    echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}✅ 前置检查完成！以下是可直接复制的路径${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "CORE_PATH=\"${BLUE}$core_abs${NC}\""
    echo -e "BINARY_PATH=\"${BLUE}$bin_abs${NC}\""
    echo ""
    echo -e "${BOLD}🧩 下一步直接复制执行：${NC}"
    echo ""
    echo -e "${GREEN}./scripts/collect_and_classify.sh \\"
    echo -e "  --core \"$core_abs\" \\"
    echo -e "  --binary \"$bin_abs\"${NC}"
    echo ""
}

# 主流程
main() {
    parse_args "$@"
    check_gdb
    check_core
    autodetect_binary
    check_debug_info
    print_final_paths
}

main "$@"