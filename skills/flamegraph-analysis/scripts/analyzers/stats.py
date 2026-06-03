#!/usr/bin/env python3
# =============================================================================
# 脚本：stats.py
# 用途：火焰图统计分析（样本数、深度、多样性等）
# 使用：python3 stats.py <folded_file> [--input FILE] [--json] [--output FILE]
# 参数：
#   <folded_file>    : folded格式的调用栈文件（位置参数或--input指定）
#   --input FILE     : 指定输入文件
#   --json           : 输出JSON格式
#   --output FILE    : 将JSON结果保存到指定文件
#   --help / -h      : 显示帮助信息
# =============================================================================
import sys
import json
import math
from collections import defaultdict

def parse_folded(content: str):
    stacks = []
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
                stacks.append((stack, count))
                total += count
            except ValueError:
                pass
    return stacks, total

def compute_stats(stacks, total):
    depth_counts = defaultdict(int)
    width_counts = defaultdict(int)
    stack_lengths = []

    for stack, count in stacks:
        frames = [f for f in stack.split(';') if f]
        depth = len(frames)
        depth_counts[depth] += count
        stack_lengths.append(depth)

    max_depth = max(stack_lengths) if stack_lengths else 0
    mean_depth = sum(d * depth_counts[d] for d in depth_counts) / total if total > 0 else 0

    depth_median = 0
    cumsum = 0
    for d in sorted(depth_counts.keys()):
        cumsum += depth_counts[d]
        if cumsum >= total * 0.5:
            depth_median = d
            break

    depth_p99 = 0
    cumsum = 0
    for d in sorted(depth_counts.keys()):
        cumsum += depth_counts[d]
        if cumsum >= total * 0.99:
            depth_p99 = d
            break

    unique_frames = set()
    for stack, _ in stacks:
        for frame in stack.split(';'):
            unique_frames.add(frame)

    shannon_entropy = 0
    for _, count in stacks:
        p = count / total if total > 0 else 0
        if p > 0:
            shannon_entropy -= p * math.log2(p)

    max_entropy = math.log2(len(stacks)) if stacks else 0
    normalized_entropy = shannon_entropy / max_entropy if max_entropy > 0 else 0

    bottleneck_type = "concentrated" if normalized_entropy < 0.3 else "distributed" if normalized_entropy > 0.7 else "mixed"

    return {
        'total_samples': total,
        'unique_stacks': len(stacks),
        'unique_frames': len(unique_frames),
        'raw_stacks': stacks,
        'depth': {
            'mean': round(mean_depth, 2),
            'median': depth_median,
            'p99': depth_p99,
            'max': max_depth,
            'distribution': dict(sorted(depth_counts.items()))
        },
        'diversity': {
            'shannon_entropy': round(shannon_entropy, 2),
            'normalized_entropy': round(normalized_entropy, 2),
            'bottleneck_type': bottleneck_type
        }
    }

def main():
    file_path = None
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""用途：火焰图统计分析（样本数、深度、多样性等）

使用：python3 stats.py <folded_file> [--input FILE] [--json] [--output FILE]

参数：
  <folded_file>    : folded格式的调用栈文件（位置参数）
  --input FILE     : 指定输入文件（可选）
  --json           : 输出JSON格式
  --output FILE    : 将JSON结果保存到指定文件
  --help / -h      : 显示此帮助信息

输出统计项：
  总样本数、唯一栈数、唯一帧数量
  调用栈深度统计（最大/最小/平均/中位数）
  多样性分析（瓶颈类型判断）
""")
        sys.exit(0)
    
    i = 1
    output_file = None
    while i < len(sys.argv):
        if sys.argv[i] == '--input' and i + 1 < len(sys.argv):
            file_path = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--output' and i + 1 < len(sys.argv):
            output_file = sys.argv[i + 1]
            i += 2
        elif file_path is None:
            file_path = sys.argv[i]
            i += 1
        else:
            i += 1
    
    if not file_path:
        print('错误：缺少输入文件')
        print('使用：python3 stats.py <folded_file> [--input FILE] [--json]')
        print('使用 --help 查看详细帮助')
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    stacks, total = parse_folded(content)
    stats = compute_stats(stacks, total)

    json_output = json.dumps(stats, indent=2)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(json_output)
        print(f'Stats saved to: {output_file}')

    if '--json' in sys.argv:
        print(json_output)
    else:
        print("=" * 80)
        print(f"Statistical Summary - Total Samples: {total}")
        print("=" * 80)
        print(f"\nUnique Stacks: {stats['unique_stacks']}")
        print(f"Unique Frames: {stats['unique_frames']}")
        print(f"\nStack Depth:")
        print(f"  Mean: {stats['depth']['mean']}")
        print(f"  Median: {stats['depth']['median']}")
        print(f"  P99: {stats['depth']['p99']}")
        print(f"  Max: {stats['depth']['max']}")
        print(f"\nDiversity Analysis:")
        print(f"  Shannon Entropy: {stats['diversity']['shannon_entropy']}")
        print(f"  Normalized Entropy: {stats['diversity']['normalized_entropy']}")
        print(f"  Bottleneck Type: {stats['diversity']['bottleneck_type']}")

if __name__ == '__main__':
    main()
