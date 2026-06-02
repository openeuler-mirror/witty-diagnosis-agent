#!/usr/bin/env python3
# =============================================================================
# 脚本：bottleneck_classifier.py
# 用途：瓶颈类型分类器（识别 CPU-bound、Lock-bound、GC-bound、IO-bound）
# 使用：python3 bottleneck_classifier.py <on_cpu_folded> [--off-cpu <file>] [--json]
# 参数：
#   <on_cpu_folded> : On-CPU folded 文件
#   --off-cpu FILE  : Off-CPU folded 文件（可选）
#   --json          : 输出 JSON 格式
#   --help / -h     : 显示帮助信息
# 分类类型：
#   cpu_bound   : CPU 计算密集型
#   lock_bound  : 锁竞争型
#   gc_bound    : 垃圾回收型
#   io_bound    : I/O 阻塞型
#   mixed       : 混合型（多种瓶颈并存）
# =============================================================================
import sys
import json
from collections import defaultdict

def parse_folded(content: str):
    stacks = []
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            try:
                count = int(count)
                stacks.append((stack, count))
            except ValueError:
                pass
    return stacks

LOCK_PATTERNS = {'pthread_mutex', 'futex_wait', 'Monitor::wait', 'sync.(*Mutex)', 'LockSupport', 'Object.wait', 'pthread_cond', 'pthread_rwlock', 'pthread_spin'}
GC_PATTERNS = {'gc_', 'GC', 'MarkSweep', 'G1', 'CollectGarbage', 'gcBgMark', 'mallocgc', 'Heap::Collect'}
IO_PATTERNS = {'read', 'write', 'recv', 'send', 'epoll', 'poll', 'select', 'vfs_', 'sk_wait', 'tcp_', 'io_schedule', 'wait_on_page'}
CPU_PATTERNS = {'cycles', 'instructions', 'CPU'}

def classify_stack(stack: str):
    frames = set(stack.split(';'))
    lock_score = sum(1 for p in LOCK_PATTERNS if any(p in f for f in frames))
    gc_score = sum(1 for p in GC_PATTERNS if any(p in f for f in frames))
    io_score = sum(1 for p in IO_PATTERNS if any(p in f for f in frames))

    if lock_score > 0 and lock_score >= gc_score and lock_score >= io_score:
        return 'lock_bound'
    elif gc_score > 0 and gc_score >= lock_score and gc_score >= io_score:
        return 'gc_bound'
    elif io_score > 0 and io_score >= lock_score and io_score >= gc_score:
        return 'io_bound'
    else:
        return 'cpu_bound'

def bottleneck_classifier(on_cpu_stacks, off_cpu_stacks=None, on_total=0, off_total=0):
    on_classification = defaultdict(int)
    for stack, count in on_cpu_stacks:
        category = classify_stack(stack)
        on_classification[category] += count

    result = {
        'on_cpu': {
            'total': on_total,
            'breakdown': {k: {'count': v, 'percent': round(v/on_total*100, 2)} for k, v in on_classification.items()}
        }
    }

    if off_cpu_stacks and off_total > 0:
        off_classification = defaultdict(int)
        for stack, count in off_cpu_stacks:
            category = classify_stack(stack)
            off_classification[category] += count

        result['off_cpu'] = {
            'total': off_total,
            'breakdown': {k: {'count': v, 'percent': round(v/off_total*100, 2)} for k, v in off_classification.items()}
        }

        total_combined = on_total + off_total
        combined = {
            'cpu_bound': on_classification.get('cpu_bound', 0),
            'lock_bound': on_classification.get('lock_bound', 0) + off_classification.get('lock_bound', 0),
            'gc_bound': on_classification.get('gc_bound', 0) + off_classification.get('gc_bound', 0),
            'io_bound': on_classification.get('io_bound', 0) + off_classification.get('io_bound', 0),
        }
        result['combined'] = {
            'total': total_combined,
            'breakdown': {k: {'count': v, 'percent': round(v/total_combined*100, 2)} for k, v in combined.items()}
        }

    primary_type = max(result['on_cpu']['breakdown'].items(), key=lambda x: x[1]['count'])[0]
    result['primary_bottleneck'] = primary_type

    thresholds = {'cpu_bound': 60, 'lock_bound': 30, 'gc_bound': 30, 'io_bound': 30, 'mixed': 40}
    main_pct = result['on_cpu']['breakdown'].get(primary_type, {}).get('percent', 0)
    if main_pct < thresholds.get(primary_type, 50):
        result['classification'] = 'mixed'
    else:
        result['classification'] = primary_type

    return result

def main():
    if len(sys.argv) < 2:
        print('Usage: bottleneck_classifier.py <on_cpu_folded> [--off-cpu <file>] [--json]')
        sys.exit(1)

    on_cpu_path = sys.argv[1]
    off_cpu_path = None
    if '--off-cpu' in sys.argv:
        idx = sys.argv.index('--off-cpu')
        if idx + 1 < len(sys.argv):
            off_cpu_path = sys.argv[idx + 1]

    with open(on_cpu_path, 'r', encoding='utf-8', errors='replace') as f:
        on_content = f.read()
    on_stacks, on_total = parse_folded(on_content)

    off_stacks = []
    off_total = 0
    if off_cpu_path:
        with open(off_cpu_path, 'r', encoding='utf-8', errors='replace') as f:
            off_content = f.read()
        off_stacks, off_total = parse_folded(off_content)

    result = bottleneck_classifier(on_stacks, off_stacks, on_total, off_total)

    if '--json' in sys.argv:
        print(json.dumps(result, indent=2))
    else:
        print("=" * 80)
        print("Bottleneck Classification")
        print("=" * 80)
        print(f"\nPrimary Bottleneck: {result['primary_bottleneck']}")
        print(f"Classification: {result['classification']}")
        print(f"\nOn-CPU Breakdown (Total: {on_total}):")
        for cat, data in result['on_cpu']['breakdown'].items():
            print(f"  {cat}: {data['count']} ({data['percent']:.2f}%)")

        if 'off_cpu' in result:
            print(f"\nOff-CPU Breakdown (Total: {off_total}):")
            for cat, data in result['off_cpu']['breakdown'].items():
                print(f"  {cat}: {data['count']} ({data['percent']:.2f}%)")

        if 'combined' in result:
            print(f"\nCombined Breakdown (Total: {result['combined']['total']}):")
            for cat, data in result['combined']['breakdown'].items():
                print(f"  {cat}: {data['count']} ({data['percent']:.2f}%)")

if __name__ == '__main__':
    main()
