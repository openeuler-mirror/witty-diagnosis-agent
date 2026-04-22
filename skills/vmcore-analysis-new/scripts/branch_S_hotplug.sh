#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_S_hotplug.sh
# 使用：bash branch_S_hotplug.sh <vmcore_path> <vmlinux_path> [src_dir]
# =============================================================================
VMCORE="${1:-/var/crash/vmcore}"
VMLINUX="${2:-/usr/lib/debug/lib/modules/$(uname -r)/vmlinux}"
SRC_DIR="${3:-}"
CRASH_CMD="crash -s ${VMLINUX} ${VMCORE}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：分支S（hotplug）完整分析"
  echo "使用：bash $0 <vmcore> <vmlinux> [src_dir]"
  exit 0
fi

HAS_SRC=false
[[ -n "${SRC_DIR}" && -d "${SRC_DIR}" ]] && HAS_SRC=true

echo "====== 分支S（hotplug）分析 ======"
echo "分析路径：$( $HAS_SRC && echo '[源码主导]' || echo '[纯vmcore]' )"
echo ""

echo "【1】日志关键信息"
${CRASH_CMD} --no_scroll << 'EOF'
log | tail -100
EOF

echo ""
echo "【2】调用栈"
${CRASH_CMD} --no_scroll << 'EOF'
bt -f
bt -l
EOF

echo ""
echo "【3】所有CPU调用栈"
${CRASH_CMD} --no_scroll << 'EOF'
bt -a
EOF

echo ""
echo "【4】内存/进程状态"
${CRASH_CMD} --no_scroll << 'EOF'
kmem -i
ps | grep " D " | head -10
mod
EOF

echo ""
echo "请参考 SKILL.md 第二节（有源码时）或第三节（无源码时），"
echo "按分支S的详细分析步骤继续深入分析。"

if $HAS_SRC; then
  echo ""
  echo "[源码路径] 源码目录：${SRC_DIR}"
  echo "遵循源码五步法："
  echo "  Step1 案发现场 → Step2 源码-汇编对齐 → Step3 逐帧追踪"
  echo "  → Step4 数据流溯源 → Step5 反事实验证"
fi
