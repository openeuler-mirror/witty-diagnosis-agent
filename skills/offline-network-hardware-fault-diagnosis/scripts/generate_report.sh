#!/bin/bash

# 网络硬件故障诊断报告生成脚本

set -e

OUTPUT_FILE="network_diagnosis_report.md"
ANALYSIS_FILE="/tmp/network_analysis_results.json"
LOG_DIR=""
SCENE_FILE="/tmp/network_diagnosis_scene.conf"

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
    echo "请先运行诊断分析脚本 (如 scripts/diagnose_network.py)"
    exit 1
fi

echo "📊 生成网络硬件故障诊断报告..."
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
    if os.path.exists(af):
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
        '# 网络硬件故障诊断报告', '',
        f"**生成时间**: {ts}",
        f"**日志目录**: {log_dir}", '',
        '---',
        '## 1. 执行摘要', ''
    ]
    
    issues = []
    all_results = data.get('all_results', [])
    for res in all_results:
        rtype = res.get('type')
        if rtype == 'ERROR_STATS': issues.append('网络硬件/驱动错误')
        if rtype == 'LINK_STATS': issues.append('链路断开或不稳定')
        if rtype == 'PERFORMANCE_STATS': issues.append('网络性能丢包')
        if rtype == 'INTERFACE_DOWN': issues.append('接口处于 DOWN 状态')
    
    report.append(f"**主要问题总结**: {', '.join(set(issues)) if issues else '未发现明显关键硬件问题'}")
    report.append(f"**识别故障场景**: {scene.get('PRIMARY_SCENE', '未明确识别场景')}")
    report.append('')
    
    report.append('## 2. 技术规格与环境')
    
    # Network Info
    info = data.get('network_info', {})
    if info:
        report.append('### 2.1 网卡硬件/驱动概览')
        if isinstance(info, dict) and 'driver' in info: # 单网卡结果
            report.append(f"- **主控设备**: {info.get('bus_info', 'N/A')}")
            report.append(f"  - 驱动: `{info.get('driver')}` (版本: {info.get('version')})")
            report.append(f"  - 固件: `{info.get('firmware')}`")
        else: # 多网卡结果
            for bdf, val in info.items():
                report.append(f"- **设备 {bdf}**:")
                report.append(f"  - 驱动: `{val.get('driver')}` (版本: {val.get('version')})")
                report.append(f"  - 固件: `{val.get('firmware')}`")
        report.append('')

    # Errors
    report.append('## 3. 关键日志分析与传导证据')
    errs = [r for r in all_results if r.get('type') in ['OS_ERROR', 'TEXT', 'MESSAGE', 'ETHTOOL_STAT']]
    if errs:
        report.append('以下为基于时序抓取到的关键故障证据：')
        report.append('')
        report.append('| 级别 | 故障描述与证据片段 | 时间戳 | 数据源文件 |')
        report.append('| :--- | :--- | :--- | :--- |')
        # 按时间排序或限制条数
        for item in errs[:15]:
            severity = item.get('severity', 'ERROR')
            desc = item.get('description', item.get('line', '-'))
            if len(desc) > 100: desc = desc[:97] + '...'
            report.append(f"| {severity} | {desc} | {item.get('timestamp','-')} | {item.get('file','-')} |")
    else:
        report.append("在扫描的日志范围内，**未发现**触发阈值的典型网络硬件报错或 PCI 总线异常。")
    report.append('')

    report.append('## 4. 根因结论与处置建议')
    if issues:
        report.append('### 4.1 诊断结论')
        report.append('根据以上日志证据链，初步判定存在**网络硬件链路层波动**或**驱动感知异常**。建议重点关注 T0 附近的硬件 SEL 报错。')
        report.append('')
        report.append('### 4.2 运维建议')
        report.append('1. **物理层自查**: 检查光模块 Rx/Tx 功率是否在正常阈值范围内，更换网线测试。')
        report.append('2. **配置核对**: 对比双机 MTU 配置及 Ethtool 物理层自协商状态。')
        report.append('3. **硬件更替**: 若 SEL 报错持续出现 PCIe Fatal Error，请考虑更换主板插槽或网卡设备。')
    else:
        report.append('目前日志证据链较为单一，建议核对对端交换机日志或应用层心跳监测记录。')
    
    with open(of, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report))
    print(f"✅ 报告已生成至: {of}")
except Exception as e:
    print(f"❌ 报告生成失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
EOF
else
    echo "# 网络故障诊断报告" > "$OUTPUT_FILE"
    echo "生成的分析文件位置: $ANALYSIS_FILE" >> "$OUTPUT_FILE"
    echo "警告：未检测到 Python3 环境，报告仅包含基础占位信息。" >> "$OUTPUT_FILE"
fi