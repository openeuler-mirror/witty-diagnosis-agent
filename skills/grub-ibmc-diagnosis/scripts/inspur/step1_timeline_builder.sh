#!/bin/bash
# 浪潮 Inspur iBMC - Step1: 启动事件时间线构建
# 用法: bash step1_timeline_builder.sh [日志根目录]
# 输出: timeline_inspur.txt

LOG_DIR="${1:-.}"
OUTPUT="timeline_inspur.txt"

echo "========================================" > $OUTPUT
echo "浪潮 iBMC 启动事件时间线" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "日志目录: $(realpath $LOG_DIR)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. SEL 事件列表（核心告警时间线，CSV格式）
SEL_CSV=$(find "$LOG_DIR" -path "*/onekeylog/log/selelist.csv" 2>/dev/null | head -1)
if [ -f "$SEL_CSV" ]; then
    echo "" >> $OUTPUT
    echo "=== [SEL] 告警事件列表（严重级别过滤）===" >> $OUTPUT
    # 提取表头
    head -1 "$SEL_CSV" >> $OUTPUT
    # 过滤严重事件
    grep -iE "(critical|non-recoverable|error|assert|power|boot|drive|raid|disk)" \
        "$SEL_CSV" | tail -80 >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/log/selelist.csv" >> $OUTPUT
fi

# 2. ErrorAnalyReport（iBMC 自动诊断报告，最重要）
ERR_RPT=$(find "$LOG_DIR" -path "*/onekeylog/log/ErrorAnalyReport.json" 2>/dev/null | head -1)
if [ -f "$ERR_RPT" ]; then
    echo "" >> $OUTPUT
    echo "=== [ErrorAnalyReport] iBMC 自动诊断报告 ===" >> $OUTPUT
    python3 -c "
import json, sys
try:
    with open('$ERR_RPT') as f:
        data = json.load(f)
    def walk(obj, path=''):
        if isinstance(obj, dict):
            for k, v in obj.items():
                walk(v, path + '.' + str(k))
        elif isinstance(obj, list):
            for i, v in enumerate(obj[:20]):
                walk(v, path + '[' + str(i) + ']')
        else:
            s = str(obj).lower()
            if any(w in s for w in ['error','fail','fault','critical','offline','degraded','assert']):
                print(path + ': ' + str(obj)[:100])
    walk(data)
except Exception as e:
    # JSON 解析失败则文本模式
    with open('$ERR_RPT') as f:
        for line in f:
            if any(w in line.lower() for w in ['error','fail','fault','critical','offline']):
                print(line.rstrip())
" 2>/dev/null >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/log/ErrorAnalyReport.json" >> $OUTPUT
fi

# 3. BMC UART 串口日志（BIOS POST 原始输出）
UART=$(find "$LOG_DIR" -path "*/onekeylog/sollog/BMCUart.log" 2>/dev/null | head -1)
if [ -f "$UART" ]; then
    echo "" >> $OUTPUT
    echo "=== [BMCUart] BIOS POST 串口输出 ===" >> $OUTPUT
    grep -iE "(error|fail|boot|press|enter|grub|kernel|panic|raid|disk|not found|loading)" \
        "$UART" | head -60 >> $OUTPUT
    echo "  --- 末尾 30 行 ---" >> $OUTPUT
    tail -30 "$UART" >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/sollog/BMCUart.log" >> $OUTPUT
fi

# 4. 运行数据（BIOS/启动配置快照）
RUNDATA=$(find "$LOG_DIR" -path "*/onekeylog/runningdata/rundatainfo.log" 2>/dev/null | head -1)
if [ -f "$RUNDATA" ]; then
    echo "" >> $OUTPUT
    echo "=== [rundatainfo] 运行时配置快照 ===" >> $OUTPUT
    grep -iE "(boot|uefi|legacy|secure|order|bios|version|firmware)" \
        "$RUNDATA" | head -40 >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/runningdata/rundatainfo.log" >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 时间线构建完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
