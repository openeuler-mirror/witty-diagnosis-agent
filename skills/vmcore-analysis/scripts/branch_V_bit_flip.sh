#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_V_bit_flip.sh
# 使用：bash branch_V_bit_flip.sh <vmcore_path> <vmlinux_path> [src_dir] [expected_value] [actual_value]
# =============================================================================
VMCORE="${1:-/var/crash/vmcore}"
VMLINUX="${2:-/usr/lib/debug/lib/modules/$(uname -r)/vmlinux}"
SRC_DIR="${3:-}"
EXPECTED_STR="${4:-}"
ACTUAL_STR="${5:-}"

CRASH_CMD="crash -s ${VMLINUX} ${VMCORE}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：分支V（bit_flip）完整分析"
  echo "使用：bash $0 <vmcore> <vmlinux> [src_dir] [expected_value] [actual_value]"
  echo "  expected_value 和 actual_value 用于验证两值 XOR 是否仅 1-bit 不同"
  exit 0
fi

HAS_SRC=false
[[ -n "${SRC_DIR}" && -d "${SRC_DIR}" ]] && HAS_SRC=true

echo "====== 分支V（bit_flip）分析 ======"
echo "分析路径：$( $HAS_SRC && echo '[源码主导]' || echo '[纯vmcore]' )"
echo ""


echo ""
echo "请参考 SKILL.md 第二节（有源码时）或第三节（无源码时），"
echo "按分支V的详细分析步骤继续深入分析。"

if $HAS_SRC; then
  echo ""
  echo "[源码路径] 源码目录：${SRC_DIR}"
  echo "遵循源码五步法："
  echo "  Step1 案发现场 → Step2 源码-汇编对齐 → Step3 逐帧追踪"
  echo "  → Step4 数据流溯源 → Step5 反事实验证"
fi

echo ""
echo "【5】Bit Flip 验证"

cat <<'EOF'
[分析步骤：如何确定“预期值(Expected)”与“实际值(Actual)”]

1. 先判断是否应优先做 Bit Flip 排查
   当现场属于未知/异常地址访问导致的崩溃（如 Page Fault、Data Abort、
   unable to handle kernel paging request，且地址并非显然的 0x0）时，
   应先排查是否存在硬件 Bit Flip，而不是立即深入业务逻辑。

2. 确定“实际值 Actual”
   Actual 一般取异常现场真正访问到的错误地址或错误值，常见来源包括：
   - x86: CR2
   - arm64: FAR
   - panic/log 中明确给出的 fault address

   注意：
   - Actual 必须是“CPU 实际访问到的现场值”
   - 不能机械地把 FAR/CR2 与一个无关值直接做 XOR

3. 反推“预期值 Expected”
   在 crash 中找到顶层异常帧对应的 PC/RIP，执行：
       dis -r <PC/RIP>
   必要时补充：
       dis -l <PC/RIP>

   根据故障指令的寻址形式，推导该指令原本逻辑上应访问的正确值或正确地址。
   常见形式包括：
   - 基址 + 偏移
   - 基址 + (索引 << 移位)
   - per-CPU 基址 + 偏移
   - 结构体字段访问
   - 页表项 / 下标 / CPU 号等数值参与运算

4. 根据语义选择辅助命令
   [A] 若更像“指针/基址/per-CPU 基址”错误
       - kmem -o
         在输出中定位崩溃 CPU 对应的 CPU N 行，取得该 CPU 的 per-CPU 基址
       - struct task_struct <addr>
       - sym <addr|symbol>
       - 必要时结合 System.map

   [B] 若更像“索引/字段/成员值”错误
       - struct <type> <addr>
       - struct <type> -o
       - vtop <vaddr>

   注意：
   - 只有在 bt / dis / 源码语义里已经有候选类型名时，才优先尝试 struct
   - 若明显是 RIP/PC、纯数值、统计量、比对字等，不要硬套 struct

5. per-CPU 场景必须保证链式一致
   若涉及 per-CPU 区域，必须保证以下对象指向同一颗逻辑 CPU：
   - sys / panic 中的 task
   - 当前分析任务
   - bt 所示崩溃 CPU
   - kmem -o 中选取的 CPU N

   否则容易串核，导致预期值推导错误。

6. dump 不完整时结论要保守
   若 sys / log 显示 PARTIAL dump，或者关键信息不全，则：
   - per-CPU
   - 模块
   - 符号
   - 结构体布局
   可能都不完全可靠，此时结论应结合 log 与其他证据交叉验证。

7. 锁定一对语义一致的“预期值 / 实际值”后，再调用脚本验证
   本脚本只负责判断给定的 Expected 与 Actual 是否符合 1-bit flip 特征，
   不负责自动推导参数，因此传入前必须先确认两者语义一致。

   调用方式：
       .script/check_bitflip.sh <expected_value> <actual_value>

   参数说明：
       expected_value    预期值（十进制或十六进制）
       actual_value      实际值（十进制或十六进制）

   示例：
       .script/check_bitflip.sh 100 134217828
       .script/check_bitflip.sh 0xDEADBEEF 0xDEACBEEF
       .script/check_bitflip.sh 0xffffffffb3a01000 0xfffffffbb3a01000


   说明：
   - 支持十进制与 0x 开头十六进制

8. 结果判定
   - 若 XOR 结果仅有 1 个 bit 不同：高度怀疑硬件 Bit Flip
   - 若不是单 bit 差异：再进入软件方向，继续排查死锁、UAF、越界写等问题
EOF