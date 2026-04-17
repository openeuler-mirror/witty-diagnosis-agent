#!/bin/bash
# ==============================================================================
# analyze_stack_overflow.sh 的副本：结尾将报告日志全文输出到终端（省略 [New LWP ...]）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

与 analyze_stack_overflow.sh 相同，但结尾会将报告日志全文输出到终端。

深入分析：栈溢出 (Stack Overflow)

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
            *) echo "Error"; exit 1 ;;
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
    echo "[*] 正在分析栈溢出..."

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
python import gdb; gdb.write('## [1] 调用栈头部 (前20层)\n'); gdb.write('    说明: 浅层栈，观察入口与浅层调用关系。\n'); gdb.write('    执行: bt 20\n')
bt 20
python import gdb; gdb.write('\n## [2] 调用栈尾部 (后20层)\n'); gdb.write('    说明: 深层栈，观察递归或深层调用是否重复同一符号。\n'); gdb.write('    执行: bt -20\n')
bt -20
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
gdb.write("\n## [3] 栈顶函数局部变量 (Frame %d，已尽量跳过 libc/信号桩)\n" % lvl)
gdb.write("    说明: 当前帧局部量，查超大栈上数组或结构体。\n")
gdb.write("    执行: frame %d; info locals\n" % lvl)
gdb.execute("frame %d" % lvl)
end
info locals
python import gdb; gdb.write('\n## [4] 人工核对\n'); gdb.write('    说明: 结合 [1][2] 是否同一函数反复出现，判断递归/栈耗尽；本段无额外 gdb 命令。\n'); gdb.write('    执行: (无，请对照上述 bt 输出)\n')
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
    echo "1. 栈溢出的核心原因是栈空间耗尽，分为无限递归和超大局部变量两种场景"
    echo "2. 无限递归场景：重点审查递归终止条件，确认边界值处理是否正确"
    echo "3. 超大局部变量场景：将栈上的大数组/结构体改为堆上动态分配"
    echo "4. 栈越界场景：排查数组越界写入破坏栈帧返回地址的问题"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 查看日志，是否有某个函数在调用栈中反复出现（递归）"
    echo "2. 检查栈顶函数的局部变量，是否有超过KB级的大数组/结构体"
    echo "3. 确认是否存在数组越界写入的逻辑"
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
