#!/bin/bash
# ==============================================================================
# collect_and_classify.sh 的副本：在原有终端输出结束后，再将完整报告日志打印到终端
# （便于现场直接查看 GDB 全文；日志很大时终端可能刷屏，可改由 less 或重定向查看）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

# 帮助
show_help() {
    cat << EOF
Usage: $(basename "$0") --core <corefile> --binary <binary>

与 collect_and_classify.sh 相同，但在摘要与绝对路径输出之后，会再把整份日志 cat 到终端。

日志报告固定输出: /tmp/core_diag/$(basename "$0" .sh)_<时间戳>.log

Required:
  -c, --core FILE      coredump 文件路径
  -b, --binary FILE    崩溃的可执行程序
EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--core) COREFILE="$2"; shift 2 ;;
            -b|--binary) BINARY="$2"; shift 2 ;;
            -h|--help) show_help; exit 0 ;;
            *) echo "Error: 未知参数 $1"; show_help; exit 1 ;;
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

# 执行 GDB 信息收集 (Python 增强版)
run_gdb_collection() {
    echo "[*] 正在收集信息..."
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
python import gdb; gdb.write('## [1] 程序与信号信息\n'); gdb.write('    说明: 进程与信号、退出原因等，用于确认终止信号与 core 是否匹配当前二进制。\n'); gdb.write('    执行: info program\n')
info program
python
import gdb
gdb.write('\n## [1b] 故障地址 si_addr (供分类)\n')
gdb.write('    说明: 部分环境下 info program 不打印 Cannot access memory；用 $_siginfo 取 SIGSEGV/SIGBUS 等 fault 地址作兜底。\n')
gdb.write('    执行: python parse_and_eval($_siginfo...)\n')
_si = None
for _expr in ('$_siginfo.si_addr', '$_siginfo._sifields._sigfault.si_addr'):
    try:
        _si = gdb.parse_and_eval(_expr)
        gdb.write('classify_si_addr: %s\n' % _si)
        break
    except Exception:
        continue
if _si is None:
    gdb.write('classify_si_addr: <unavailable>\n')
end
python import gdb; gdb.write('\n## [2] 完整调用栈 (C 层)\n'); gdb.write('    说明: 全栈帧、参数与局部变量线索，供场景分类与后续深入分析。\n'); gdb.write('    执行: bt full\n')
bt full
python import gdb; gdb.write('\n## [3] 寄存器\n'); gdb.write('    说明: 崩溃时通用寄存器与 PC。\n'); gdb.write('    执行: info registers\n')
info registers
python import gdb; gdb.write('\n## [4] 反汇编 (PC 附近)\n'); gdb.write('    说明: 崩溃指令前后汇编。\n'); gdb.write('    执行: disas $pc-20,$pc+40\n')
disas $pc-20,$pc+40
python import gdb; gdb.write('\n## [5] 内存映射\n'); gdb.write('    说明: 进程地址空间映射。\n'); gdb.write('    执行: info proc mappings\n')
info proc mappings
python import gdb; gdb.write('\n## [6] 线程信息\n'); gdb.write('    说明: 线程列表及各线程回溯。\n'); gdb.write('    执行: info threads; thread apply all bt\n')
info threads
thread apply all bt
python import gdb; gdb.write('\n## [7] Python 层增强分析 (可选)\n'); gdb.write('    说明: 尝试 py-bt / py-locals（需 debug 包，失败则降级）。\n'); gdb.write('    执行: py-bt; py-locals\n')
python
try:
    gdb.write("--- 尝试获取 Python 调用栈 (py-bt) ---\n")
    gdb.execute("py-bt")
    gdb.write("\n--- 尝试获取 Python 局部变量 (py-locals) ---\n")
    gdb.execute("py-locals")
except Exception:
    gdb.write("[Python 栈不可用]\n")
    gdb.write("提示：若为 Python 进程，请安装 python3-dbg 或 python3-debuginfo\n")
end
quit
GDBEOF
        gdb --quiet --batch -x "$GDB_CMD" "$BINARY" "$COREFILE"
        rm -f "$GDB_CMD"
    } > "$LOG_FILE" 2>&1
    echo "[*] 信息收集完成: $LOG_FILE"
}

# 智能场景分类
classify_scenario() {
    local LOG="$LOG_FILE"
    local SCENARIO="" DESC="" NEXT_CMD=""
    echo "[*] 正在分析故障场景..."
    local SIGNAL
    SIGNAL=$(grep -m1 "Program terminated with signal" "$LOG" | sed 's/.*signal //' | sed 's/,.*//' | tr -d '[:space:]\r')

    # SIGSEGV / SIGBUS：共用 fault 地址与主线程栈深；SIGBUS 单独场景名（更关注对齐、映射区）
    if [[ "$SIGNAL" == "SIGSEGV" || "$SIGNAL" == "SIGBUS" ]]; then
        # 故障地址：优先 GDB 文案「Cannot access memory」；若无则使用 [1b] 中 classify_si_addr（$_siginfo）
        local FAULT_ADDR FAULT_ADDR_LOWER
        local -i IS_NULLPTR=0
        FAULT_ADDR=$(grep -m1 "Cannot access memory at address" "$LOG" 2>/dev/null | awk '{print $NF}')
        if [[ -z "$FAULT_ADDR" ]]; then
            FAULT_ADDR=$(grep -m1 '^classify_si_addr:' "$LOG" 2>/dev/null | sed 's/^classify_si_addr:[[:space:]]*//' | tr -d '\r')
            [[ "$FAULT_ADDR" == "<unavailable>" ]] && FAULT_ADDR=""
        fi
        FAULT_ADDR_LOWER="${FAULT_ADDR,,}"
        if [[ "$FAULT_ADDR" == "(nil)" ]] || [[ "$FAULT_ADDR_LOWER" =~ ^0x0+$ ]]; then
            IS_NULLPTR=1
        fi
        # 仅统计 ## [2] bt full 与 ## [3] 之间的栈帧行（不含 thread apply all）。
        local STACK_DEPTH
        STACK_DEPTH=$(awk '
            /^## \[2\]/{p=1; next}
            /^## \[3\]/{p=0; next}
            p && /^Thread[[:space:]]+[0-9]+[[:space:]]*\(/{p=0; next}
            p && /^#[0-9]+[[:space:]]/{c++}
            END { print c+0 }' "$LOG")
        if [[ "$IS_NULLPTR" -eq 1 ]]; then
            SCENARIO="nullptr"; DESC="空指针访问"
            NEXT_CMD="./scripts/analyze_nullptr.sh --core $COREFILE --binary $BINARY"
        elif [[ $STACK_DEPTH -gt 50 ]]; then
            SCENARIO="stack_overflow"; DESC="栈溢出"
            NEXT_CMD="./scripts/analyze_stack_overflow.sh --core $COREFILE --binary $BINARY"
        elif [[ "$SIGNAL" == "SIGSEGV" ]]; then
            SCENARIO="memory_corrupt"; DESC="内存破坏/野指针/越界"
            NEXT_CMD="./scripts/analyze_memory_corrupt.sh --core $COREFILE --binary $BINARY"
        else
            SCENARIO="sigbus"; DESC="总线错误 (常见: 未对齐访问、映射文件/非映射区间访问等；请重点看 [5] 映射与 [4] 反汇编)"
            NEXT_CMD="./scripts/analyze_sigbus.sh --core $COREFILE --binary $BINARY"
        fi
    elif [[ "$SIGNAL" == "SIGABRT" ]]; then
        SCENARIO="abort"; DESC="程序主动终止 (堆破坏/异常/断言)"
        NEXT_CMD="./scripts/analyze_abort.sh --core $COREFILE --binary $BINARY"
    elif [[ "$SIGNAL" == "SIGFPE" ]]; then
        SCENARIO="divzero"; DESC="算术异常 (除零)"
        NEXT_CMD="./scripts/analyze_divzero.sh --core $COREFILE --binary $BINARY"
    elif [[ "$SIGNAL" == "SIGILL" || "$SIGNAL" == "SIGSYS" || "$SIGNAL" == "SIGXCPU" || "$SIGNAL" == "SIGXFSZ" ]]; then
        SCENARIO="other"; DESC="少见信号 ($SIGNAL)，无专项下钻脚本；请通读本日志 [1]-[7] 人工分析"
        NEXT_CMD="(无专项) 信息已收集于上述报告日志"
    else
        SCENARIO="unknown"; DESC="未单独建模的信号 ($SIGNAL)"; NEXT_CMD="N/A"
    fi

    echo ""
    echo "========================================"
    {
        echo ""
        echo "=== Coredump 诊断报告 (第一步) ==="
        echo "报告日志: $LOG_FILE"
        echo "[结论]"
        echo "场景: $SCENARIO"
        echo "描述: $DESC"
        echo "[下一步操作]"
        echo "$NEXT_CMD"
    } | tee -a "$LOG_FILE"
    echo "========================================"
    echo "报告日志绝对路径: $(realpath "$LOG_FILE")"

    # 与 collect_and_classify.sh 的差异：将日志再输出到终端；过滤 GDB 线程刷屏行 [New LWP ...]（磁盘上的 LOG_FILE 仍为完整原文）
    echo ""
    echo "========================================"
    echo "[*] 以下为报告日志全文（终端已省略 [New LWP ...] 行；完整原文见上述路径）"
    echo "========================================"
    grep -Ev '^\[New LWP [0-9]+\]' "$LOG_FILE"
}

# 主流程
parse_args "$@"
run_gdb_collection
classify_scenario
