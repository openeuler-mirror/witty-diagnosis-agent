#!/bin/bash
# ==============================================================================
# analyze_memory_corrupt.sh 的副本：结尾将报告日志全文输出到终端（省略 [New LWP ...]）
# ==============================================================================

# 参数
COREFILE=""
BINARY=""
LOG_FILE=""

# 帮助
show_help() {
    cat << EOF
Usage: $(basename "$0") --core <core> --binary <binary>

与 analyze_memory_corrupt.sh 相同，但结尾会将报告日志全文输出到终端。

深入分析：内存破坏/野指针/越界访问

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

# 执行专项分析 (寄存器+内存鉴定增强版)
analyze() {
    echo "[*] 正在执行内存破坏专项分析..."

    {
        echo "----------------------------------------------------------------------"
        echo " [GDB] 单次会话仅加载一次 core。命令通过「-x 临时脚本」传入（避免部分环境下 --batch 从 stdin 读命令无效）；小节标题用 Python gdb.write，不依赖 shell/内置 echo。"
        echo "   gdb --quiet --batch -x <临时文件> \"$BINARY\" \"$COREFILE\""
        echo "----------------------------------------------------------------------"
        echo ""
        echo "若出现 warning: core file may not match specified executable file，请尽量使用与生成 core 时一致的解释器路径。"
        echo ""
        GDB_CMD="$(mktemp)" || exit 1
        cat <<'GDBEOF' > "$GDB_CMD"
set pagination off
python import gdb; gdb.write('## [1] 完整调用栈\n'); gdb.write('    说明: 全栈回溯，定位非法访存所在调用链。\n'); gdb.write('    执行: bt full\n')
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
gdb.write("\n## [2] 崩溃现场 (Frame %d，已跳过 pthread_kill/raise/信号桩至首帧业务代码)\n" % lvl)
gdb.write("    说明: 当前帧源码、参数与局部量（若栈顶仅为 libc 递信号，此处比固定 frame 0 更有用）。\n")
gdb.write("    执行: frame %d; list; info args; info locals\n" % lvl)
gdb.execute("frame %d" % lvl)
end
list
info args
info locals
python import gdb; gdb.write('\n'); gdb.write('## [3] 寄存器状态\n'); gdb.write('    说明: 通用寄存器现场，对照非法地址落在哪个寄存器。\n'); gdb.write('    执行: info registers\n')
info registers
python import gdb; gdb.write('\n'); gdb.write('## [4] 关键寄存器指向的内存内容 (x86_64)\n'); gdb.write('    说明: 对当前已选帧（见 [2]）上「疑似用户态指针」的 RDI/RSI/RDX 做 x/32gx；小整数(tid 等)已用区间过滤。\n'); gdb.write('    执行: 仅当 0x100000 < reg < 0x800000000000 时 x/32gx\n')
if ($rdi > 0x100000 && $rdi < 0x0000800000000000)
  x/32gx $rdi
end
if ($rsi > 0x100000 && $rsi < 0x0000800000000000)
  x/32gx $rsi
end
if ($rdx > 0x100000 && $rdx < 0x0000800000000000)
  x/32gx $rdx
end
python import gdb; gdb.write('\n'); gdb.write('## [5] 崩溃点反汇编 (带机器码)\n'); gdb.write('    说明: PC 附近带机器码反汇编，锁定具体访存指令。\n'); gdb.write('    执行: 与下一行相同（disas /r 围绕当前 PC）\n')
disas /r $pc-50,$pc+50
python import gdb; gdb.write('\n'); gdb.write('## [6] 内存映射 (用于判断地址合法性)\n'); gdb.write('    说明: 对照崩溃地址是否落在已映射区间。\n'); gdb.write('    执行: info proc mappings\n')
info proc mappings
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
    echo "内存破坏通常是‘结果’，而不是‘原因’。要重点关注崩溃前最近的内存写入操作。"
    echo "如果崩溃地址看起来像‘乱码’(如 0xdeadbeef 或随机值)，大概率是野指针或释放后使用(UAF)。"
    echo "结合代码审查，重点检查数组下标、指针生命周期和 memcpy/memset 的长度参数。"
    echo ""
    echo "【人工分析 Checklist】"
    echo "1. 打开日志，查看 '[3] 寄存器状态'，确认是哪个寄存器导致了访问错误"
    echo "2. 查看 '[4] 关键寄存器指向的内存内容'，判断内存状态："
    echo "   - 全 0x0 或全 0xff？ -> 可能已释放或未初始化"
    echo "   - 看起来像正常数据但程序依然崩溃？ -> 可能是 Use-After-Free (UAF)"
    echo "3. 查看 '[5] 崩溃点反汇编'，确认是在执行什么指令 (mov/cmp/call)"
    echo "4. 结合 '[6] 内存映射'，确认崩溃地址是否在堆区、栈区或已被 munmap"
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
