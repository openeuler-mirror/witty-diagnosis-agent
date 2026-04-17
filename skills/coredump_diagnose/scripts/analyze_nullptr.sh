#!/bin/bash
# ==============================================================================
# analyze_nullptr.sh 的副本：在方法论与「报告日志绝对路径」输出之后，
# 再将整份报告日志打印到终端（便于现场查看；终端省略 [New LWP ...] 行）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

# 帮助
show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

与 analyze_nullptr.sh 相同，但在结尾会将报告日志全文输出到终端（已过滤 [New LWP ...]）。

深入分析：空指针访问 (NULL Pointer Dereference)

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
    echo "[*] 正在执行空指针专项分析..."

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
python import gdb; gdb.write('## [1] 完整调用栈\n'); gdb.write('    说明: 全栈回溯，定位空指针解引用发生在哪一帧。\n'); gdb.write('    执行: bt full\n')
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
gdb.write("    说明: 当前帧对应崩溃指令所在函数。\n")
gdb.write("    执行: frame %d; list; info args; info locals; disas\n" % lvl)
gdb.execute("frame %d" % lvl)
end
python import gdb; gdb.write('\n## [3] 源码上下文\n'); gdb.write('    说明: 当前位置附近源码行（需调试符号）。\n'); gdb.write('    执行: list\n')
list
python import gdb; gdb.write('\n## [4] 函数参数\n'); gdb.write('    说明: 当前帧形参，追踪哪一指针为 NULL。\n'); gdb.write('    执行: info args\n')
info args
python import gdb; gdb.write('\n## [5] 局部变量\n'); gdb.write('    说明: 当前帧局部变量。\n'); gdb.write('    执行: info locals\n')
info locals
python import gdb; gdb.write('\n## [6] 崩溃点反汇编 (确认读/写操作)\n'); gdb.write('    说明: 崩溃点指令流，区分对 NULL 的读还是写。\n'); gdb.write('    执行: disas\n')
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
    echo "1. 打开日志，找到 [2] 所选帧，确认哪个变量/指针为 NULL"
    echo "2. 查看 info args/locals，确认该指针的赋值状态"
    echo "3. 向上回溯调用栈，检查该指针是在哪一层函数调用中被置空"
    echo "4. 修复时增加非空校验的防御性编程"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 确认空指针的名称和来源（参数/局部变量/全局变量）"
    echo "2. 确认是读操作还是写操作触发的崩溃"
    echo "3. 回溯指针的赋值路径，找到未初始化/置空的原因"
    echo "========================================"
    echo "报告日志绝对路径: $(realpath "$LOG_FILE")"
}

# 与 analyze_nullptr.sh 的差异：将日志再输出到终端（省略 [New LWP ...]）
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
