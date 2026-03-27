#!/bin/bash
# 浪潮 Inspur iBMC - Step2: 硬件层异常检查（RAID / 磁盘 / 组件）
# 用法: bash step2_hardware_check.sh [日志根目录]
# 输出: hardware_check_inspur.txt

LOG_DIR="${1:-.}"
OUTPUT="hardware_check_inspur.txt"

echo "========================================" > $OUTPUT
echo "浪潮 iBMC 硬件层故障检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. RAID 日志（支持多控制器 raid0.log / raid1.log ...）
echo "=== [RAID] 控制器日志 ===" >> $OUTPUT
RAID_LOGS=$(find "$LOG_DIR" -path "*/onekeylog/log/raid*.log" 2>/dev/null)
if [ -n "$RAID_LOGS" ]; then
    echo "$RAID_LOGS" | while read f; do
        echo "--- 文件: $(basename $f) ---" >> $OUTPUT
        grep -iE "(degraded|offline|rebuild|fail|error|missing|foreign|optimal|critical|pd |vd )" \
            "$f" | tail -40 >> $OUTPUT
    done
else
    echo "[WARN] 未找到 onekeylog/log/raid*.log" >> $OUTPUT
fi

# 2. 组件识别日志
COMP_LOG=$(find "$LOG_DIR" -path "*/onekeylog/component/component.log" 2>/dev/null | head -1)
if [ -f "$COMP_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [component] 硬件组件识别日志 ===" >> $OUTPUT
    grep -iE "(error|fail|not found|absent|removed|added|disk|drive|raid|slot)" \
        "$COMP_LOG" | tail -50 >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/component/component.log" >> $OUTPUT
fi

# 3. 寄存器原始数据（硬件故障寄存器状态）
REG_DATA=$(find "$LOG_DIR" -path "*/onekeylog/runningdata/RegRawData.json" 2>/dev/null | head -1)
if [ -f "$REG_DATA" ]; then
    echo "" >> $OUTPUT
    echo "=== [RegRawData] 硬件寄存器状态（非零异常值）===" >> $OUTPUT
    python3 -c "
import json
NORMAL = {'0','0x0','null','None','','true','false','Normal','OK','Good','Present','Enabled'}
try:
    with open('$REG_DATA') as f:
        data = json.load(f)
    def walk(obj, path='', depth=0):
        if depth > 6: return
        if isinstance(obj, dict):
            for k, v in obj.items(): walk(v, path+'.'+str(k), depth+1)
        elif isinstance(obj, list):
            for i, v in enumerate(obj[:30]): walk(v, path+'['+str(i)+']', depth+1)
        else:
            s = str(obj)
            if s not in NORMAL and len(s) < 80:
                print(path + ': ' + s)
    walk(data)
except Exception as e:
    print('解析失败:', e)
" 2>/dev/null | head -60 >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/runningdata/RegRawData.json" >> $OUTPUT
fi

# 4. SEL 磁盘/存储相关告警
SEL_CSV=$(find "$LOG_DIR" -path "*/onekeylog/log/selelist.csv" 2>/dev/null | head -1)
if [ -f "$SEL_CSV" ]; then
    echo "" >> $OUTPUT
    echo "=== [SEL] 磁盘/存储告警 ===" >> $OUTPUT
    grep -iE "(drive|disk|storage|raid|volume|array|hdd|ssd|nvme)" \
        "$SEL_CSV" | tail -40 >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 硬件层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
