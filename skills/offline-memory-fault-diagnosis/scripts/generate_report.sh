#!/bin/bash

# 内存故障诊断报告生成脚本

set -e

OUTPUT_FILE="memory_diagnosis_report.md"
ANALYSIS_FILE="/tmp/memory_analysis_results.json"
LOG_DIR=""
SCENE_FILE="/tmp/memory_diagnosis_scene.conf"

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
    echo "请先运行诊断分析脚本 (如 scripts/diagnose_memory.py)"
    exit 1
fi

echo "📊 生成内存故障诊断报告..."
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
        '# 内存故障诊断报告', '',
        f"**生成时间**: {ts}",
        f"**日志目录**: {log_dir}", '',
        '## 1. 执行摘要', ''
    ]
    
    issues = []
    mem_info = data.get('memory_info', {})
    
    # 查找所有结果中的错误
    all_res = data.get('all_results', [])
    ecc_errors = [r for r in all_res if 'ECC' in str(r).upper() or 'UCE' in str(r).upper()]
    oom_kills = [r for r in all_res if 'OOM' in str(r).upper() or 'KILLED' in str(r).upper()]
    
    if ecc_errors: issues.append('通过分析发现严重内存硬件错误 (ECC/UCE)')
    if oom_kills: issues.append('检测到内存耗竭事件 (OOM Killer)')
    
    report.append(f"**主要问题**: {', '.join(issues) if issues else '未发现严重问题'}")
    report.append(f"**故障场景**: {scene.get('PRIMARY_SCENE', '未识别 (请参考 Step 1 指南判定)')}")
    report.append('')
    
    report.append('## 2. 技术分析')
    
    # 2.1 证据校验矩阵 (Step 3 核心)
    report.append('### 2.1 证据校验矩阵 (Cross-Examination)')
    report.append('依据《离线内存故障诊断指南》Step 3 要求，对核心结论执行证据完整性校验：')
    report.append('')
    report.append('| 校验维度 | 状态 | 支撑证据片段 (Raw Log Snippet) |')
    report.append('| :--- | :--- | :--- |')
    report.append('| **E1: 时序连续性** | [待人工确认] | 需要对齐 T0-2h 到 T0 之间的关键变更记录 |')
    report.append('| **E2: 物理/逻辑同一性** | [待人工确认] | 需要确认 OS 报告的 DIMM 槽位与 iBMC 硬件槽位一致 |')
    report.append('| **E3: 现象排他性** | [待人工确认] | 需要排除 BIOS 配置、CPU 调度及其他平行部件的干扰 |')
    report.append('')

    # 2.2 Memory Info
    if mem_info:
        total = mem_info.get('mem_total_gb') or mem_info.get('MemTotal')
        if total and isinstance(total, int) and total > 1000: # Assuming it's in KB
            total = round(total / 1024 / 1024, 2)
        
        slab = mem_info.get('slab_kb') or mem_info.get('Slab')
        
        report.append('### 2.2 硬件概览')
        report.append(f"- **总物理内存**: {total if total else '?'} GB")
        report.append(f"- **Slab 占用**: {slab if slab else '?'} kB")
        report.append('')

    # 2.3 Error Analysis
    report.append('### 2.3 故障记录分析')
    important_errors = [r for r in all_res if r.get('type') in ['MESSAGE', 'DMESG_ERROR', 'TEXT']]
    if important_errors:
        report.append(f"提取了 {len(important_errors)} 条关键错误/日志记录。")
        report.append('| 描述 | 时间 | 原始日志片段 |')
        report.append('|------|------|--------------|')
        for item in important_errors[:20]:
            desc = item.get('description', '未知错误')
            ts = item.get('timestamp', '?')
            line = item.get('line', '')[:100]
            if len(item.get('line', '')) > 100: line += '...'
            report.append(f"| {desc} | {ts} | `{line}` |")
    else:
        report.append("未在分析周期内发现相关报错。")
    report.append('')

    report.append('## 3. 根因结论与修复建议')
    
    # 根因逻辑细化
    if ecc_errors:
        # 区分 CE 和 UCE
        is_uce = any('UCE' in str(r).upper() or 'UNCORRECTABLE' in str(r).upper() for r in ecc_errors)
        report.append('### 3.1 结论 (MEMORY_ECC_ERROR)')
        if is_uce:
            report.append("- **原因**: 内存颗粒发生**不可纠正硬件损坏 (UCE)**，触发 MCE / Kernel Panic。")
            report.append("- **修复建议**: 立即更换故障 DIMM。参考 iBMC 日志确定的物理槽位坐标。")
        else:
            report.append("- **原因**: 内存颗粒发生**可纠正错误 (CE) 累积**，达到系统设定的单位翻转阈值。")
            report.append("- **修复建议**: 记录 DIMM 插槽位置，执行内存压力测试。若 CE 持续增长，建议停机插拔或更换。")
    elif oom_kills:
        report.append('### 3.1 结论 (MEMORY_OOM_KILLER)')
        # 简单区分 Slab 或 App
        is_slab_high = mem_info.get('slab_kb', 0) > (total * 1024 * 1024 * 0.3) if total else False
        if is_slab_high:
            report.append("- **原因**: **内核 Slab 占用过高** 导致可用内存耗竭，触发 OOM。")
            report.append("- **修复建议**: 检查内核模块（fd, dentry, inode）是否存在泄露，升级内核补丁。")
        else:
            report.append("- **原因**: **特定应用程序/业务进程** 内存申请超过物理限制，触发隔离机制。")
            report.append("- **修复建议**: 优化业务 JVM 堆大小或 Nginx 缓存配置，增加物理内存或设置监控预警。")
    else:
        report.append("- **初步研判**: 系统内存状态目前处于统计性波动或轻微过载，建议配合 Step 0 的时间轴继续回溯。")
    
    report.append('')
    report.append('---')
    report.append('*该报告由内存故障诊断 Skill 自动生成。*')
    
    with open(of, 'w', encoding='utf-8') as f:
        f.write('\n'.join(report))
    print(f"✅ 报告已生成至: {of}")
except Exception as e:
    print(f"❌ 报告生成失败: {e}")
    sys.exit(1)
EOF
else
    echo "⚠️  未找到python3，生成简易报告。"
    echo "# 内存故障诊断报告" > "$OUTPUT_FILE"
    echo "生成时间: $(date)" >> "$OUTPUT_FILE"
fi

exit 0