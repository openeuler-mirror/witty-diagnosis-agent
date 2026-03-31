#!/bin/bash

# CPU故障诊断报告生成脚本

set -e

OUTPUT_FILE="cpu_diagnosis_report.md"
ANALYSIS_FILE="/tmp/cpu_analysis_results.json"
LOG_DIR=""
SCENE_FILE="/tmp/cpu_diagnosis_scene.conf"

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --analysis)
            ANALYSIS_FILE="$2"
            shift 2
            ;;
        --log-dir)
            LOG_DIR="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

if [ ! -f "$ANALYSIS_FILE" ]; then
    echo "❌ 错误: 未找到分析结果文件 $ANALYSIS_FILE"
    echo "请先运行诊断分析脚本 (如 scripts/diagnose_cpu.py)"
    exit 1
fi

echo "📊 生成CPU故障诊断报告..."
echo "输出文件: $OUTPUT_FILE"

# 导出变量供Python使用
export ANALYSIS_FILE
export OUTPUT_FILE
export LOG_DIR
export SCENE_FILE

if command -v python3 &> /dev/null; then
    python3 << 'EOF'
import json, os, sys
from datetime import datetime

af = os.environ.get('ANALYSIS_FILE')
of = os.environ.get('OUTPUT_FILE')
sf = os.environ.get('SCENE_FILE')
ld = os.environ.get('LOG_DIR', '未知')

try:
    data = {}
    with open(af, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    scene = {}
    if os.path.exists(sf):
        try:
            with open(sf, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        scene[k.strip()] = v.strip()
        except: pass

    ts = data.get('timestamp', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    log_dir = data.get('log_dir', ld)
    
    report = [
        '# CPU故障诊断报告', '',
        f"**生成时间**: {ts}",
        f"**日志目录**: {log_dir}", '',
        '## 1. 执行摘要', ''
    ]
    
    issues = []
    tmp_sum = data.get('temperature_summary', {})
    if tmp_sum.get('high_temps'): issues.append('CPU过热')
    err_sum = data.get('error_summary', {})
    if err_sum.get('critical_errors'): issues.append('CPU硬件错误')
    freq_sum = data.get('frequency_summary', {})
    if freq_sum.get('throttling_count', 0) > 0: issues.append('CPU降频')
    
    report.append(f"**主要问题**: {', '.join(issues) if issues else '未发现严重问题'}")
    report.append(f"**故障场景**: {scene.get('PRIMARY_SCENE', '未识别 (请参考 Step 1 指南判定)')}")
    report.append('')
    
    report.append('## 2. 技术分析')
    
    # CPU Info
    info = data.get('cpu_info', {})
    if info:
        report.append('### 2.1 硬件概览')
        report.append(f"- **型号**: {info.get('model', '未知')}")
        report.append(f"- **架构**: {info.get('sockets','?')} Socket / {info.get('cores_per_socket','?')} Core")
        report.append(f"- **频率**: {info.get('frequency_mhz','?')} MHz")
        report.append('')

    # Temperature
    report.append('### 2.2 温度分析')
    ht = tmp_sum.get('high_temps', [])
    if ht:
        report.append(f"发现 {len(ht)} 条关键高温记录。")
        report.append('| 传感器 | 温度 | 时间 |')
        report.append('|--------|------|------|')
        for item in ht[:5]:
            report.append(f"| {item.get('sensor','?')} | {item.get('temperature','?')}C | {item.get('timestamp','?')} |")
    else:
        report.append("温度读数正常。")
    report.append('')

    # Errors
    report.append('### 2.3 错误分析')
    ce = err_sum.get('critical_errors', [])
    if ce:
        report.append(f"发现 {len(ce)} 条关键错误记录。")
        report.append('| 描述 | 时间 | 数据源 |')
        report.append('|------|------|--------|')
        for item in ce[:10]:
            report.append(f"| {item.get('description','?')} | {item.get('timestamp','?')} | {item.get('source_file','?')} |")
    else:
        report.append("未发现严重错误日志。")
    report.append('')

    report.append('## 3. 根因结论与措施')
    report.append('- **初步结论**: 参见上述分析项。建议结合时序一致性进行人工核验。')
    report.append('- **处置建议**: 控制负载，优化散热，必要时检查硬件连通性。')
    
    with open(of, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report))
    print(f"✅ 报告已生成至: {of}")
except Exception as e:
    print(f"❌ 报告生成失败: {e}")
    sys.exit(1)
EOF
else
    echo "⚠️  未找到python3，生成简易报告。"
    echo "# CPU故障诊断报告" > "$OUTPUT_FILE"
    echo "生成时间: $(date)" >> "$OUTPUT_FILE"
    echo "分析结果见: $ANALYSIS_FILE" >> "$OUTPUT_FILE"
fi

exit 0