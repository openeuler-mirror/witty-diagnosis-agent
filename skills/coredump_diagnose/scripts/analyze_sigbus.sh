#!/bin/bash
# ==============================================================================
# SIGBUS 总线错误专项分析（与 analyze_divzero 等脚本同构：-x 临时脚本 + gdb.write）
# ==============================================================================

COREFILE=""
BINARY=""
LOG_FILE=""

show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

深入分析：总线错误 (SIGBUS)
- 典型场景：未对齐访问、mmap 映射文件截断/删除、磁盘满、硬件/驱动异常等

日志报告固定输出: /tmp/core_diag/$(basename "$0" .sh)_<时间戳>.log

参数：
  -c, --core FILE      coredump 文件
  -b, --binary FILE    可执行程序
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--core) COREFILE="$2"; shift 2 ;;
            -b|--binary) BINARY="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "Error: 未知参数"; exit 1 ;;
        esac
    done
    [[ -z "$COREFILE" ]] && { echo "Error: 缺少 --core"; exit 1; }
    [[ -z "$BINARY" ]] && { echo "Error: 缺少 --binary"; exit 1; }
    local CORE_DIAG_BASE="/tmp/core_diag"
    mkdir -p "$CORE_DIAG_BASE"
    local SCRIPT_BASE TS
    SCRIPT_BASE="$(basename "$0" .sh)"
    TS="$(date +%Y%m%d%H%M%S)"
    LOG_FILE="$CORE_DIAG_BASE/${SCRIPT_BASE}_${TS}.log"
}

analyze() {
    echo "[*] 正在执行 SIGBUS 总线错误专项分析..."

    {
        echo "----------------------------------------------------------------------"
        echo " [GDB] 单次会话；-x 临时脚本 + Python gdb.write（同 analyze_memory_corrupt.sh）。"
        echo "   gdb --quiet --batch -x <临时文件> \"$BINARY\" \"$COREFILE\""
        echo "----------------------------------------------------------------------"
        echo ""
        echo "若出现 warning: core file may not match specified executable file，请尽量使用与生成 core 时一致的解释器路径。"
        echo ""
        GDB_CMD="$(mktemp)" || exit 1
        cat <<'GDBEOF' > "$GDB_CMD"
set pagination off
python import gdb; gdb.write('## [1] 完整调用栈\n'); gdb.write('    说明: 定位 SIGBUS 所在业务路径。\n'); gdb.write('    执行: bt full\n')
bt full
python
import gdb
fi = gdb.newest_frame()
lvl = 0
while fi:
    n = fi.name() or ""
    sigtramp = False
    try:
        t = fi.type()
        if hasattr(gdb, "SIGTRAMP_FRAME") and t == gdb.SIGTRAMP_FRAME:
            sigtramp = True
        elif hasattr(gdb, "FRAME_SIGTRAMP") and t == gdb.FRAME_SIGTRAMP:
            sigtramp = True
    except Exception:
        pass
    skip = (
        sigtramp
        or n == "<signal handler called>"
        or (not n.strip() and lvl < 8)
        or "pthread_kill" in n
        or n in ("raise", "gsignal", "__GI_raise")
        or "__GI_raise" in n
    )
    if not skip:
        break
    nxt = fi.older()
    if nxt is None:
        break
    fi = nxt
    lvl += 1
gdb.write("\n## [2] 崩溃现场 (Frame %d，已跳过 pthread_kill/raise/信号桩)\n" % lvl)
gdb.write("    说明: 源码与局部量；SIGBUS 常与访存指令、对齐相关。\n")
gdb.write("    执行: frame %d; list; info args; info locals\n" % lvl)
gdb.execute("frame %d" % lvl)
end
list
info args
info locals
python import gdb; gdb.write('\n## [3] 寄存器状态\n'); gdb.write('    说明: 对照 PC 与地址相关寄存器。\n'); gdb.write('    执行: info registers\n')
info registers
python import gdb; gdb.write('\n## [4] 崩溃点反汇编 (带机器码)\n'); gdb.write('    说明: 是否涉及对齐访存、向量访存等。\n'); gdb.write('    执行: disas /r $pc-40,$pc+40\n')
disas /r $pc-40,$pc+40
python import gdb; gdb.write('\n## [5] 内存映射 (重点: 文件映射 MAP_SHARED、匿名映射与崩溃地址)\n'); gdb.write('    说明: 对照崩溃地址是否落在被截断的映射、可执行栈等异常区。\n'); gdb.write('    执行: info proc mappings\n')
info proc mappings
quit
GDBEOF
        gdb --quiet --batch -x "$GDB_CMD" "$BINARY" "$COREFILE"
        rm -f "$GDB_CMD"
    } > "$LOG_FILE" 2>&1
}

generate_report() {
    echo ""
    echo "========================================"
    echo "分析完成！"
    echo ""
    echo "【核心方法论】"
    echo "SIGBUS 总线错误的核心是 CPU 内存访问请求在硬件 / 内核层面失效，区别于 SIGSEGV 的非法地址访问。"
    echo "生产环境多数场景，要么是 ARM 等架构下的内存未对齐访问，要么是 mmap 映射的文件被截断、删除或磁盘空间耗尽。"
    echo "排查优先确认运行架构，再回溯崩溃前的文件映射、大文件 IO 相关业务逻辑。"
    echo "排除以上场景后，再排查物理内存损坏、内核驱动异常等底层问题。"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 确认目标架构与对齐要求（尤其 ARM）；对照 [4] 反汇编是否未对齐/向量访存"
    echo "2. 对照 [5] 映射：崩溃地址是否落在文件映射区；是否可能发生截断、删除或磁盘满"
    echo "3. 结合 [1][2] 业务栈，回溯 mmap/大文件读写在崩溃前的路径"
    echo "========================================"
    echo "报告日志绝对路径: $(realpath "$LOG_FILE")"
}

dump_log_to_terminal() {
    echo ""
    echo "========================================"
    echo "[*] 以下为报告日志全文（终端已省略 [New LWP ...] 行；完整原文见上述路径）"
    echo "========================================"
    grep -Ev '^\[New LWP [0-9]+\]' "$LOG_FILE"
}

parse_args "$@"
analyze
generate_report
dump_log_to_terminal
