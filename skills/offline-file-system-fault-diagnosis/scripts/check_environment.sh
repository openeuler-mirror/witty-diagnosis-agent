#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-dir) LOG_DIR="$2"; shift 2 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

PASS=true
FOUND_DIRS=()
FOUND_FILES=()

check_ok()   { echo "  ✅ $1"; }
check_warn() { echo "  ⚠️  $1"; }
check_fail() { echo "  ❌ $1"; PASS=false; }

echo "=============================="
echo " 存储日志诊断环境检查"
echo " (磁盘硬件 & 文件系统)"
echo "=============================="
echo ""

echo "[1/2] 检查日志目录..."
if [[ -d "$LOG_DIR" ]]; then
    check_ok "日志根目录存在：$LOG_DIR"
else
    check_fail "日志根目录不存在：$LOG_DIR"
    exit 1
fi

echo ""
echo "[2/2] 检查子目录和日志文件..."

SUB_DIRS=("ibmc_logs" "infocollect_logs" "messages")

for sub_dir in "${SUB_DIRS[@]}"; do
    DIR_PATH="$LOG_DIR/$sub_dir"
    if [[ -d "$DIR_PATH" ]]; then
        check_ok "子目录存在：$sub_dir/"
        FOUND_DIRS+=("$sub_dir")
        
        case "$sub_dir" in
            "ibmc_logs")
                FILES=("sel.db" "sel.tar" "selelist.csv" "current_event.txt" "sensor_info.txt")
                ;;
            "infocollect_logs")
                FILES=("disk_smart.txt" "sasraidlog.txt" "sashbalog.txt" "dmesg.txt" "iostat.txt" "diskmap.txt")
                ;;
            "messages")
                FILES=("messages" "syslog" "dmesg" "kern.log")
                ;;
        esac
        
        for file in "${FILES[@]}"; do
            FILE_PATH="$DIR_PATH/$file"
            if [[ -f "$FILE_PATH" ]]; then
                SIZE=$(wc -l < "$FILE_PATH" 2>/dev/null || echo "0")
                if [[ "$SIZE" -gt 0 ]]; then
                    check_ok "  └─ $file ($SIZE 行)"
                    FOUND_FILES+=("$sub_dir/$file")
                fi
            fi
        done
        
        for file in "$DIR_PATH"/*; do
            if [[ -f "$file" ]]; then
                filename=$(basename "$file")
                if [[ "$filename" =~ \.(txt|log|csv|json)$ ]]; then
                    if [[ ! " ${FOUND_FILES[*]} " =~ " $sub_dir/$filename " ]]; then
                        SIZE=$(wc -l < "$file" 2>/dev/null || echo "0")
                        if [[ "$SIZE" -gt 0 ]]; then
                            check_ok "  └─ $filename ($SIZE 行)"
                            FOUND_FILES+=("$sub_dir/$filename")
                        fi
                    fi
                fi
            fi
        done
    else
        check_warn "子目录不存在：$sub_dir/"
    fi
done

echo ""
echo "=============================="
if [[ "$PASS" == "true" && ${#FOUND_FILES[@]} -gt 0 ]]; then
    echo "✅ Environment check passed!"
    echo ""
    echo "诊断配置："
    echo "  日志根目录 : $LOG_DIR"
    echo "  可用子目录 : ${#FOUND_DIRS[@]} 个 (${FOUND_DIRS[*]})"
    echo "  可用文件   : ${#FOUND_FILES[@]} 个"
    echo ""
    
    cat > /tmp/fs_diagnosis_env.conf <<EOF
LOG_DIR="$LOG_DIR"
FOUND_DIRS="${FOUND_DIRS[*]}"
FOUND_FILES="${FOUND_FILES[*]}"
EOF
    echo "环境配置已保存到 /tmp/fs_diagnosis_env.conf"
    exit 0
else
    echo "❌ Environment check FAILED! 请修复上述问题后重试。"
    echo ""
    echo "期望的目录结构："
    echo "  <日志根目录>/"
    echo "  ├── ibmc_logs/          # iBMC 硬件日志"
    echo "  ├── infocollect_logs/   # 系统信息收集日志"
    echo "  └── messages/           # 操作系统日志"
    exit 1
fi
