#!/usr/bin/env python3
"""
joint_analysis.py — On/Off-CPU 联合分析工具
功能：数据对齐、时间分解、交叉验证、根因链输出
"""
import sys, json, re
from collections import defaultdict

def parse_folded(content):
    stacks, total = {}, 0
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2 and parts[1].isdigit():
            stacks[parts[0]] = int(parts[1])
            total += int(parts[1])
    return stacks, total

def align_check(on_stacks, on_total, off_stacks, off_total):
    """数据对齐验证"""
    on_pids = set()
    off_pids = set()
    for s in on_stacks:
        pid = s.split(';')[0] if ';' in s else s
        on_pids.add(pid)
    for s in off_stacks:
        pid = s.split(';')[0] if ';' in s else s
        off_pids.add(pid)

    common_pids = on_pids & off_pids
    sample_ratio = (on_total / off_total) if off_total > 0 else 0

    return {
        'on_pids': len(on_pids),
        'off_pids': len(off_pids),
        'common_pids': len(common_pids),
        'pid_match_pct': round(len(common_pids) / max(len(on_pids | off_pids), 1) * 100, 1),
        'on_samples': on_total,
        'off_samples': off_total,
        'sample_ratio': round(sample_ratio, 2),
    }

def time_decomposition(categories):
    """墙钟时间分解"""
    decomposition = {}
    total = sum(c['samples'] for c in categories) if categories else 0
    for c in categories:
        pct = round(c['samples'] / total * 100, 1) if total > 0 else 0
        decomposition[c['category']] = {'samples': c['samples'], 'percent': pct}
    return decomposition

def joint_analysis(on_file, off_file):
    with open(on_file, 'r', encoding='utf-8') as f:
        on_stacks, on_total = parse_folded(f.read())
    with open(off_file, 'r', encoding='utf-8') as f:
        off_stacks, off_total = parse_folded(f.read())

    # 对齐验证
    align = align_check(on_stacks, on_total, off_stacks, off_total)

    # 公共栈路径的 blocking_ratio（支持前缀匹配）
    # 如果 Off-CPU 栈以 On-CPU 栈的部分帧开头，视为匹配
    joint = []
    matched_off = set()
    
    # 先尝试精确匹配
    for stack in sorted(set(on_stacks.keys()) & set(off_stacks.keys()), 
                        key=lambda s: -(off_stacks[s] / (on_stacks[s] + off_stacks[s]) if (on_stacks[s] + off_stacks[s]) > 0 else 0))[:20]:
        on_c = on_stacks[stack]
        off_c = off_stacks[stack]
        ratio = round(off_c / (on_c + off_c), 3) if (on_c + off_c) > 0 else 0
        joint.append({
            'stack': stack, 'match_type': 'exact',
            'on_samples': on_c, 'off_samples': off_c,
            'blocking_ratio': ratio,
            'type': 'cpu_bound' if ratio < 0.1 else 'io_bound' if ratio > 0.7 else 'mixed'
        })
        matched_off.add(stack)
    
    # 再尝试前缀匹配（逐级父路径匹配）
    for on_stack, on_c in sorted(on_stacks.items(), key=lambda x: -x[1])[:50]:
        if on_stack in matched_off:
            continue
        # 生成所有父路径
        parts = on_stack.split(';')
        found_match = False
        for i in range(len(parts)-1, 0, -1):
            prefix = ';'.join(parts[:i])
            matching_off = [s for s in off_stacks if s.startswith(prefix + ';') and s not in matched_off]
            if matching_off:
                off_c = sum(off_stacks[s] for s in matching_off)
                total = on_c + off_c
                if total > 0:
                    ratio = round(off_c / total, 3)
                    joint.append({
                        'stack': on_stack + ' -> ' + prefix + ';...', 'match_type': 'prefix',
                        'on_samples': on_c, 'off_samples': off_c,
                        'blocking_ratio': ratio,
                        'type': 'cpu_bound' if ratio < 0.1 else 'io_bound' if ratio > 0.7 else 'mixed'
                    })
                    for s in matching_off:
                        matched_off.add(s)
                    found_match = True
                    break
    
    joint.sort(key=lambda x: -x['blocking_ratio'])
    joint = joint[:20]



    # 时间分解
    try:
        from offcpu_classifier import classify_offcpu, OFFCPU_PATTERNS
        off_stacks_list = [(s, c) for s, c in off_stacks.items()]
        cat_stats = classify_offcpu(off_stacks_list)
        decomposition = []
        for cat, stats in cat_stats.items():
            if stats['samples'] > 0:
                decomposition.append({'category': cat, 'samples': stats['samples']})
        time_dec = time_decomposition(decomposition)
    except ImportError:
        time_dec = {}
        off_ratio = round(off_total / (on_total + off_total) * 100, 1) if (on_total + off_total) > 0 else 0
        time_dec = {'on_cpu_percent': round(100 - off_ratio, 1), 'off_cpu_percent': off_ratio}

    return {
        'alignment': align,
        'on_cpu': {'samples': on_total, 'stacks': len(on_stacks)},
        'off_cpu': {'samples': off_total, 'stacks': len(off_stacks)},
        'joint_stacks': joint[:20],
        'time_decomposition': time_dec,
        'wall_clock': {
            'total_samples': on_total + off_total,
            'on_cpu_pct': round(on_total / (on_total + off_total) * 100, 1) if (on_total + off_total) > 0 else 0,
            'off_cpu_pct': round(off_total / (on_total + off_total) * 100, 1) if (on_total + off_total) > 0 else 0,
        }
    }

def main():
    import argparse
    parser = argparse.ArgumentParser(description='On/Off-CPU Joint Analysis')
    parser.add_argument('--on-cpu', required=True, help='On-CPU folded file')
    parser.add_argument('--off-cpu', required=True, help='Off-CPU folded file')
    parser.add_argument('--align', action='store_true', help='Only run alignment check')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')
    parser.add_argument('--output', help='Output JSON file')
    args = parser.parse_args()

    result = joint_analysis(args.on_cpu, args.off_cpu)

    if args.align:
        a = result['alignment']
        print(f"对齐验证报告:")
        print(f"  时间窗口: On-CPU={a['on_samples']} Off-CPU={a['off_samples']}")
        print(f"  进程ID匹配: {a['common_pids']}/{max(a['on_pids'],a['off_pids'])} ({a['pid_match_pct']}%)")
        pf = "✅" if a['pid_match_pct'] >= 80 else "⚠️"
        print(f"  PID一致性: {pf}")
        sr = a['sample_ratio']
        print(f"  采样比例: 1:{sr} (on:off)")
        return

    output = json.dumps(result, indent=2)
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output)
        print(f"Output: {args.output}")
    else:
        print(output)

if __name__ == '__main__':
    main()
