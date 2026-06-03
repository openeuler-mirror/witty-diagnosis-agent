#!/usr/bin/env python3
# =============================================================================
# 脚本：diff.py
# 用途：差分火焰图分析工具（对比两个 folded 文件）
# 使用：python3 diff.py <baseline_folded> <target_folded> [--json|--folded|--text]
# 参数：
#   <baseline_folded> : 基线 folded 文件
#   <target_folded>   : 目标 folded 文件
#   --json            : 输出 JSON 格式详细分析
#   --folded          : 输出差分折叠格式（用于生成差分火焰图）
#   --text            : 输出文本格式摘要
# 说明：参考 FlameGraph 的 difffolded.pl 实现双列输出格式
# =============================================================================
import sys
import json
from collections import defaultdict

def parse_folded(content: str):
    stacks = {}
    total = 0
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            try:
                count = int(count)
                stacks[stack] = count
                total += count
            except ValueError:
                pass
    return stacks, total

def diff_analysis(baseline_stacks, baseline_total, target_stacks, target_total):
    all_stacks = set(baseline_stacks.keys()) | set(target_stacks.keys())

    diff_results = []
    for stack in all_stacks:
        baseline_count = baseline_stacks.get(stack, 0)
        target_count = target_stacks.get(stack, 0)
        diff = target_count - baseline_count

        baseline_pct = (baseline_count / baseline_total * 100) if baseline_total > 0 else 0
        target_pct = (target_count / target_total * 100) if target_total > 0 else 0
        pct_diff = target_pct - baseline_pct

        if abs(diff) >= 1 or abs(pct_diff) >= 0.1:
            diff_results.append({
                'stack': stack,
                'baseline_count': baseline_count,
                'target_count': target_count,
                'diff': diff,
                'baseline_pct': round(baseline_pct, 2),
                'target_pct': round(target_pct, 2),
                'pct_diff': round(pct_diff, 2),
                'change_type': 'new' if baseline_count == 0 else 'removed' if target_count == 0 else 'changed'
            })

    diff_results.sort(key=lambda x: -abs(x['diff']))

    significant_changes = [d for d in diff_results if abs(d['pct_diff']) >= 1.0]

    return {
        'baseline_total': baseline_total,
        'target_total': target_total,
        'total_diff': target_total - baseline_total,
        'all_changes': diff_results[:50],
        'significant_changes': significant_changes[:20]
    }

def generate_diff_folded(baseline_stacks, target_stacks, threshold: int = 0):
    """
    生成差分折叠格式，用于生成差分火焰图
    格式: stack (+/-)count
    """
    all_stacks = set(baseline_stacks.keys()) | set(target_stacks.keys())
    diff_lines = []
    
    for stack in all_stacks:
        baseline_count = baseline_stacks.get(stack, 0)
        target_count = target_stacks.get(stack, 0)
        diff = target_count - baseline_count
        
        if abs(diff) > threshold:
            sign = '+' if diff > 0 else ''
            diff_lines.append(f"{stack} {sign}{diff}")
    
    return '\n'.join(diff_lines)

def main():
    if len(sys.argv) < 3:
        print('Usage: diff.py <baseline_folded> <target_folded> [--json|--folded|--text]')
        print('  --json    : 输出JSON格式详细分析')
        print('  --folded  : 输出差分折叠格式（用于生成差分火焰图）')
        print('  --text    : 输出文本格式摘要')
        sys.exit(1)

    baseline_path = sys.argv[1]
    target_path = sys.argv[2]

    with open(baseline_path, 'r', encoding='utf-8', errors='replace') as f:
        baseline_content = f.read()
    with open(target_path, 'r', encoding='utf-8', errors='replace') as f:
        target_content = f.read()

    baseline_stacks, baseline_total = parse_folded(baseline_content)
    target_stacks, target_total = parse_folded(target_content)

    # 处理 --folded 参数（difffolded.pl 格式）
    if '--folded' in sys.argv:
        print(generate_diff_folded(baseline_stacks, target_stacks))
        return

    result = diff_analysis(baseline_stacks, baseline_total, target_stacks, target_total)

    if '--json' in sys.argv:
        print(json.dumps(result, indent=2))
    else:
        print("=" * 80)
        print(f"Diff Analysis: Baseline ({baseline_total}) vs Target ({target_total})")
        print(f"Total Diff: {result['total_diff']:+d}")
        print("=" * 80)

        print("\n### Significant Changes (>1% difference)")
        print(f"{'Stack':<50} {'Baseline':<10} {'Target':<10} {'Diff':<10}")
        print("-" * 85)
        for change in result['significant_changes'][:15]:
            print(f"{change['stack'][:50]:<50} {change['baseline_pct']:>8.2f}% {change['target_pct']:>8.2f}% {change['pct_diff']:>+8.2f}%")

        print("\n### New Stacks (in target but not baseline)")
        new_stacks = [c for c in result['all_changes'] if c['change_type'] == 'new']
        for change in new_stacks[:10]:
            print(f"  + {change['stack']} ({change['target_count']})")

        print("\n### Removed Stacks (in baseline but not target)")
        removed_stacks = [c for c in result['all_changes'] if c['change_type'] == 'removed']
        for change in removed_stacks[:10]:
            print(f"  - {change['stack']} ({change['baseline_count']})")

if __name__ == '__main__':
    main()
