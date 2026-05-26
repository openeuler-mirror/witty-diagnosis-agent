#!/bin/bash
# ==============================================================================
# analyze_divzero.sh 的副本：结尾将报告日志全文输出到终端（省略 [New LWP ...]）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

# 帮助
show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

与 analyze_divzero.sh 相同，但结尾会将报告日志全文输出到终端。

深入分析：算术错误 (SIGFPE)
- 通常为：除零错误 (Division by Zero)

日志报告固定输出: /tmp/core_diag/$(basename "$0" .sh)_<时间戳>.log

参数：
  -c, --core FILE      coredump 文件
  -b, --binary FILE    可执行程序
EOF
}

# 解析参数
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

# 执行专项分析
analyze() {
    echo "[*] 正在执行算术错误专项分析..."

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
python import gdb; gdb.write('## [1] 完整调用栈\n'); gdb.write('    说明: 定位除零/取模发生在哪一调用路径。\n'); gdb.write('    执行: bt full\n')
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
gdb.write("    说明: 源码、参数与局部量，确认除数变量来源。\n")
gdb.write("    执行: frame %d; list; info args; info locals\n" % lvl)
gdb.execute("frame %d" % lvl)
end
list
info args
info locals
python import gdb; gdb.write('\n## [3] 寄存器状态\n'); gdb.write('    说明: 整型除法常体现在寄存器中，核对除数是否为 0。\n'); gdb.write('    执行: info registers\n')
info registers
python import gdb; gdb.write('\n## [4] 崩溃点反汇编\n'); gdb.write('    说明: 查找 div/idiv 及操作数，确认哪一侧为 0。\n'); gdb.write('    执行: disas\n')
disas
quit
GDBEOF
        gdb --quiet --batch -x "$GDB_CMD" "$BINARY" "$COREFILE"
        rm -f "$GDB_CMD"
    } > "$LOG_FILE" 2>&1
}

# 生成结论
generate_report() {
    echo ""
    echo "========================================"
    echo "分析完成！"
    echo ""
    echo "【核心方法论】"
    echo "这是最容易定位的故障之一，直接查看崩溃点的除法运算即可。"
    echo "不仅要关注‘除数’本身，还要关注取模运算 (%)，它也会触发 SIGFPE。"
    echo "修复时不要只在崩溃处加判断，最好在数据入口处就校验合法性。"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 查看反汇编，找到 div/idiv 指令，确认哪个寄存器/变量是除数"
    echo "2. 查看 'info registers' 或 'info locals'，确认该值是否为 0"
    echo "3. 向上回溯，看看这个 0 是计算出来的，还是外部传入的参数"
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
