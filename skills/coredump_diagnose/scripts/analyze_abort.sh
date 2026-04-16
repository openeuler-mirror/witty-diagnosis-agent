#!/bin/bash
# ==============================================================================
# analyze_abort.sh 的副本：结尾将报告日志全文输出到终端（省略 [New LWP ...]）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

# 帮助
show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

与 analyze_abort.sh 相同，但结尾会将报告日志全文输出到终端。

深入分析：程序主动终止 (SIGABRT)
- 常见子场景：堆损坏 (Double Free / Corruption)、C++ 未捕获异常、断言失败

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
    echo "[*] 正在执行 SIGABRT 专项分析 (重点排查堆损坏)..."

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
python import gdb; gdb.write('## [1] 完整调用栈\n'); gdb.write('    说明: 查找 __GI_abort、malloc_printerr、__cxa_throw 等特征帧。\n'); gdb.write('    执行: bt full\n')
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
gdb.write("\n## [2] 崩溃现场 (Frame %d，已跳过 pthread_kill/raise/信号桩；若为 abort 本身则保留该帧)\n" % lvl)
gdb.write("    说明: 栈顶源码上下文，对应 abort/断言位置。\n")
gdb.write("    执行: frame %d; list\n" % lvl)
gdb.execute("frame %d" % lvl)
end
list
python import gdb; gdb.write('\n## [3] 线程栈帧信息\n'); gdb.write('    说明: 各线程最近栈深，排查多线程下堆损坏或锁。\n'); gdb.write('    执行: thread apply all bt 10\n')
thread apply all bt 10
python import gdb; gdb.write('\n## [4] C++ 异常信息\n'); gdb.write('    说明: 尝试打印当前 C++ 异常类型名（无异常或符号缺失则可能失败）。\n'); gdb.write('    执行: print *(char*)__cxa_current_exception_type()->name()\n')
python
try:
    gdb.execute("print *(char*)__cxa_current_exception_type()->name()")
except Exception:
    gdb.write("[无法获取C++异常类型]\n")
end
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
    echo "SIGABRT 是程序‘自杀’，通常是因为发现了不可恢复的错误（如堆结构破坏）。"
    echo "如果调用栈中包含 \`__libc_message\` 或 \`malloc_printerr\`，这是 Glibc 堆损坏的铁证。"
    echo "堆损坏的‘案发时间’通常早于崩溃时间，请重点审查崩溃前最后几次内存分配/释放操作。"
    echo "对于 C++ 程序，确认是否在析构函数中抛出了异常，或者异常没有被 catch。"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 查看调用栈，确认是在 'malloc/free' 里崩的，还是在 '__cxa_throw' 里崩的"
    echo "2. 如果是堆损坏，回忆代码中最近是否修改了内存管理相关逻辑"
    echo "3. 检查是否有数组越界写（尤其是在堆上分配的数组）"
    echo "4. 检查是否有同一个指针被 free/delete 了两次"
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
