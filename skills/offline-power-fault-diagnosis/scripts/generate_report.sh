#!/bin/bash

# 电源故障诊断报告生成脚本

set -e

OUTPUT_FILE="power_diagnosis_report.md"
ANALYSIS_FILE="/tmp/power_analysis_results.json"
LOG_DIR=""
SCENE_FILE="/tmp/power_diagnosis_scene.conf"

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
    echo "请先运行诊断分析脚本 (如 scripts/diagnose_power.py)"
    exit 1
fi

echo "📊 生成电源故障诊断报告..."
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
    
    scene_conf = {}
    if os.path.exists(sf):
        try:
            with open(sf, 'r') as f:
                for line in f:
                    if '=' in line:
                        k, v = line.strip().split('=', 1)
                        scene_conf[k.strip()] = v.strip()
        except: pass

    ts = data.get('timestamp', datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
    log_dir = data.get('log_dir', ld)
    scene_label = data.get('scene', scene_conf.get('SCENE', 'UNKNOWN'))
    
    report = [
        '# 电源故障诊断报告', '',
        f"**生成时间**: {ts}",
        f"**日志目录**: {log_dir}", '',
        '## 1. 执行摘要', ''
    ]
    
    issues = []
    err_sum = data.get('error_summary', {})
    total_errors = err_sum.get('total_errors', 0)
    if total_errors > 0: issues.append(f'发现 {total_errors} 条电源错误')
    
    psu_info = data.get('psu_info', {})
    if psu_info:
        issues.append(f"检测到 {psu_info.get('count', '?')} 个 PSU 模块")
    
    report.append(f"**主要问题**: {', '.join(issues) if issues else '未发现明显电源问题'}")
    report.append(f"**故障场景**: {scene_label}")
    report.append('')
    
    report.append('## 2. 技术分析')
    
    # PSU Info
    if psu_info:
        report.append('### 2.1 电源模块状态')
        states = psu_info.get('states', {})
        if states:
            report.append('| PSU | 状态 |')
            report.append('|-----|------|')
            for p, s in sorted(states.items()):
                report.append(f"| {p} | {s} |")
        else:
            report.append("未获取到具体 PSU 状态。")
        report.append('')

    # Voltage details
    voltages = data.get('voltage_details', [])
    if voltages:
        report.append('### 2.2 电压分析')
        report.append('| 传感器 | 数值 | 状态 |')
        report.append('|--------|------|------|')
        for v in voltages[:10]:
            report.append(f"| {v.get('sensor','?')} | {v.get('value','?')}V | {v.get('status','?')} |")
        report.append('')

    # Error details
    report.append('### 2.3 关键错误记录')
    top_errors = err_sum.get('top_errors', [])
    if top_errors:
        report.append('| 类别 | 时间 | 日志片段 |')
        report.append('|------|------|----------|')
        for item in top_errors[:10]:
            report.append(f"| {item.get('tag','?')} | {item.get('timestamp','?')} | {item.get('line','?')} |")
    else:
        report.append("未发现严重电源错误日志。")
    report.append('')

    report.append('## 3. 根因结论与修复建议')
    report.append('针对识别到的场景，建议参考如下措施：')
    
    if scene_label == "POWER_LOSS":
        report.append('- **结论**: 检测到交流输入丢失或电源输出丢失。')
        report.append('- **建议**: 检查外部 PDU 供电；检查电源线缆连接；对调 PSU 测试判定硬件损坏。')
    elif scene_label == "VOLTAGE_ANOMALY":
        report.append('- **结论**: 电压传感器报告数值超出范围。')
        report.append('- **建议**: 检查母板 VRM；升级固件；检查是否由于负载瞬时峰值导致。')
    else:
        report.append('- **结论**: 需结合具体日志片段进一步判定。')
        report.append('- **建议**: 详查 iBMC 及 OS 消息日志；执行硬件压力测试。')
    
    report.append('')
    report.append('---')
    report.append('*报告由离线电源故障诊断工具自动生成*')
    
    with open(of, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report))
    print(f"✅ 报告已生成至: {of}")
except Exception as e:
    print(f"❌ 报告生成失败: {e}")
    sys.exit(1)
EOF
else
    echo "⚠️  未找到python3，生成简易报告。"
    echo "# 电源故障诊断报告" > "$OUTPUT_FILE"
    echo "生成时间: $(date)" >> "$OUTPUT_FILE"
    echo "分析结果见: $ANALYSIS_FILE" >> "$OUTPUT_FILE"
fi

exit 0