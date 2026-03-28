#!/usr/bin/env bash
# =============================================================================
# check_environment.sh — 文件系统日志诊断环境预检脚本（离线分析）
#
# 用途：在执行任何诊断分析之前，验证所有必要的日志文件是否存在且可用。
#       若检查失败则以非 0 退出码退出，上层脚本或 Skill 流程必须强制中止。
#       本脚本仅检查日志文件，不执行任何在线系统命令。
#
# 参数：
#   --log-dir PATH   日志文件所在目录（默认：当前目录）
#
# 使用示例：
#   ./check_environment.sh
#   ./check_environment.sh --log-dir /path/to/logs
#
# 输出：
#   成功：打印 "✅ Environment check passed!" 并退出码 0
#   失败：打印具体错误信息并退出码 1
# =============================================================================

set -euo pipefail

# ---------- 默认值 ----------
LOG_DIR="."

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

PASS=true
FOUND_FILES=()

# ---------- 辅助函数 ----------
check_ok()   { echo "  ✅ $1"; }
check_warn() { echo "  ⚠️  $1"; }
check_fail() { echo "  ❌ $1"; PASS=false; }

echo "=============================="
echo " 文件系统日志诊断环境检查"
echo "=============================="
echo ""

# ---------- 1. 检查日志目录 ----------
echo "[1/2] 检查日志目录..."
if [[ -d "$LOG_DIR" ]]; then
    check_ok "日志目录存在：$LOG_DIR"
else
    check_fail "日志目录不存在：$LOG_DIR"
    exit 1
fi

# ---------- 2. 检查日志文件 ----------
echo ""
echo "[2/2] 检查日志文件..."

LOG_FILES=(
    "kernel_dmesg.log"
    "systemd_boot.log"
    "fsck_check.log"
    "system_messages.log"
    "disk_layout_lsblk.log"
    "disk_uuid_blkid.log"
    "mount_config_fstab.log"
    "disk_health_smart.log"
)

for log_file in "${LOG_FILES[@]}"; do
    FILE_PATH="$LOG_DIR/$log_file"
    if [[ -f "$FILE_PATH" ]]; then
        SIZE=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")
        if [[ "$SIZE" -gt 0 ]]; then
            check_ok "$log_file 存在（$SIZE 行）"
            FOUND_FILES+=("$log_file")
        else
            check_warn "$log_file 存在但为空"
        fi
    fi
done

if [[ ${#FOUND_FILES[@]} -eq 0 ]]; then
    check_fail "未找到任何有效的日志文件"
    echo ""
    echo "  支持的日志文件："
    for f in "${LOG_FILES[@]}"; do
        echo "    - $f"
    done
else
    check_ok "共找到 ${#FOUND_FILES[@]} 个有效日志文件"
fi

# ---------- 汇总 ----------
echo ""
echo "=============================="
if [[ "$PASS" == "true" && ${#FOUND_FILES[@]} -gt 0 ]]; then
    echo "✅ Environment check passed!"
    echo ""
    echo "诊断配置："
    echo "  日志目录 : $LOG_DIR"
    echo "  可用文件 : ${#FOUND_FILES[@]} 个"
    echo ""
    # 将配置导出到临时文件，供其他脚本复用
    cat > /tmp/fs_diagnosis_env.conf <<EOF
LOG_DIR="$LOG_DIR"
FOUND_FILES="${FOUND_FILES[*]}"
EOF
    echo "环境配置已保存到 /tmp/fs_diagnosis_env.conf"
    exit 0
else
    echo "❌ Environment check FAILED! 请修复上述问题后重试。"
    exit 1
fi
