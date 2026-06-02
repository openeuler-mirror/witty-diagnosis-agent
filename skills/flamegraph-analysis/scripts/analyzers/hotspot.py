#!/usr/bin/env python3
# =============================================================================
# 脚本：hotspot.py
# 用途：热点函数分析（通用多语言支持）
# 使用：python3 hotspot.py <folded_file> [--input FILE] [--top N] [--json] [--output FILE]
# 参数：
#   <folded_file>    : folded格式的调用栈文件（位置参数或--input指定）
#   --input FILE     : 指定输入文件
#   --top N          : 输出前N个热点（默认20）
#   --json           : 输出JSON格式
#   --output FILE    : 将JSON结果保存到指定文件
#   --help / -h      : 显示帮助信息
# =============================================================================
import sys
import json
from collections import defaultdict

# 语言/框架识别模式（可扩展）
LANGUAGE_PATTERNS = {
    'java': {
        'suffix': '[j]',
        'patterns': ['io/netty', 'org/apache', 'com/google', 'java/lang', 'java/util']
    },
    'go': {
        'suffix': '[g]',
        'patterns': ['runtime.', 'net.', 'sync.', 'os.', 'encoding/json']
    },
    'python': {
        'suffix': '[p]',
        'patterns': ['__pycache__', '.pyc', '/usr/lib/python']
    },
    'cpp': {
        'suffix': '[c]',
        'patterns': ['std::', 'boost::', 'std.', 'boost.']
    },
    'rust': {
        'suffix': '[r]',
        'patterns': ['std::', 'core::', 'alloc::', 'tokio::']
    }
}

def parse_folded(content: str):
    """解析 folded 格式文件（通用）"""
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

def top_down_analysis(stacks, total, top_n=20):
    """自顶向下分析（通用）"""
    tree = defaultdict(lambda: {'count': 0, 'children': defaultdict(int)})

    for stack, count in stacks:
        frames = stack.split(';')
        if not frames:
            continue
        root = frames[0]
        tree[root]['count'] += count
        if len(frames) > 1:
            child = frames[1]
            tree[root]['children'][child] += count

    results = []
    for name, data in sorted(tree.items(), key=lambda x: -x[1]['count']):
        pct = (data['count'] / total * 100) if total > 0 else 0
        results.append({
            'rank': len(results) + 1,
            'frame': name,
            'count': data['count'],
            'percent': round(pct, 2),
            'children': dict(sorted(data['children'].items(), key=lambda x: -x[1])[:5])
        })
        if len(results) >= top_n:
            break

    return results

def bottom_up_analysis(stacks, total, top_n=20):
    """自底向上分析（通用）"""
    leaf_counts = defaultdict(int)
    leaf_contexts = defaultdict(list)

    for stack, count in stacks:
        frames = stack.split(';')
        if not frames:
            continue
        leaf = frames[-1]
        leaf_counts[leaf] += count
        if len(frames) > 1:
            context = ';'.join(frames[-2:])
            leaf_contexts[leaf].append((context, count))

    results = []
    for leaf, count in sorted(leaf_counts.items(), key=lambda x: -x[1]):
        pct = (count / total * 100) if total > 0 else 0
        contexts = sorted(leaf_contexts[leaf], key=lambda x: -x[1])[:3]
        results.append({
            'rank': len(results) + 1,
            'frame': leaf,
            'count': count,
            'percent': round(pct, 2),
            'top_contexts': [{'context': c, 'count': n} for c, n in contexts]
        })
        if len(results) >= top_n:
            break

    return results

def frame_pattern_analysis(stacks, total, patterns, top_n=20):
    """按指定模式分析（通用）"""
    pattern_counts = defaultdict(int)
    pattern_stacks = defaultdict(list)

    for stack, count in stacks:
        frames = stack.split(';')
        for frame in frames:
            for pattern in patterns:
                if pattern.lower() in frame.lower():
                    pattern_counts[frame] += count
                    pattern_stacks[frame].append((stack, count))
                    break

    results = []
    for frame, count in sorted(pattern_counts.items(), key=lambda x: -x[1]):
        pct = (count / total * 100) if total > 0 else 0
        contexts = sorted(pattern_stacks[frame], key=lambda x: -x[1])[:3]
        results.append({
            'rank': len(results) + 1,
            'name': frame,
            'frame': frame,
            'count': count,
            'percent': round(pct, 2),
            'top_contexts': [{'context': c[0], 'count': c[1]} for c in contexts]
        })
        if len(results) >= top_n:
            break

    return results

def language_frame_analysis(stacks, total, language_suffix, top_n=20):
    """通用语言帧分析，根据后缀识别"""
    frame_counts = defaultdict(int)
    frame_contexts = defaultdict(list)

    for stack, count in stacks:
        frames = stack.split(';')
        for i, frame in enumerate(frames):
            if frame.endswith(language_suffix):
                frame_counts[frame] += count
                context = ';'.join(frames[max(0, i-2):i+1])
                frame_contexts[frame].append((context, count))

    results = []
    for frame, count in sorted(frame_counts.items(), key=lambda x: -x[1]):
        pct = (count / total * 100) if total > 0 else 0
        contexts = sorted(frame_contexts[frame], key=lambda x: -x[1])[:3]
        results.append({
            'rank': len(results) + 1,
            'name': frame,
            'frame': frame,
            'count': count,
            'percent': round(pct, 2),
            'top_contexts': [{'context': c[0], 'count': c[1]} for c in contexts]
        })
        if len(results) >= top_n:
            break

    return results

def detect_language(stacks):
    """自动检测主要编程语言"""
    language_counts = defaultdict(int)
    
    for stack, count in stacks:
        frames = stack.split(';')
        for frame in frames:
            for lang, config in LANGUAGE_PATTERNS.items():
                if frame.endswith(config['suffix']):
                    language_counts[lang] += count
                    break
    
    if not language_counts:
        return None
    
    return max(language_counts, key=language_counts.get)

def main():
    file_path = None
    top_n = 20
    output_file = None
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""用途：热点函数分析（通用多语言支持）

使用：python3 hotspot.py <folded_file> [--input FILE] [--top N] [--json] [--output FILE]

参数：
  <folded_file>    : folded格式的调用栈文件（位置参数）
  --input FILE     : 指定输入文件（可选）
  --top N          : 输出前N个热点，默认20
  --json           : 输出JSON格式
  --output FILE    : 将JSON结果保存到指定文件
  --help / -h      : 显示此帮助信息

支持的语言：Java ([j]), Go ([g]), Python ([p]), C++ ([c]), Rust ([r])

输出：
  自顶向下分析：按调用栈根节点统计
  自底向上分析：按调用栈叶节点统计
  语言特定分析：针对检测到的语言进行分析
  框架热点分析：针对常见框架进行分析
""")
        sys.exit(0)
    
    i = 1
    while i < len(sys.argv):
        if sys.argv[i] == '--input' and i + 1 < len(sys.argv):
            file_path = sys.argv[i + 1]
            i += 2
        elif sys.argv[i] == '--top' and i + 1 < len(sys.argv):
            top_n = int(sys.argv[i + 1])
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
        print('使用：python3 hotspot.py <folded_file> [--input FILE] [--top N] [--json]')
        print('使用 --help 查看详细帮助')
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    stacks, total = parse_folded(content)
    
    # 自动检测语言
    detected_lang = detect_language(stacks)
    
    # 通用框架模式（跨语言）
    common_patterns = [
        'processSelectedKeys', 'fireChannelRead', 'flush', 'write', 'read',
        'handleRequest', 'doRead', 'doWrite', 'dispatch', 'execute',
        'run', 'call', 'invoke', 'handle', 'process', 'service'
    ]

    result = {
        'total_samples': total,
        'unique_stacks': len(stacks),
        'detected_language': detected_lang,
        'top_down': top_down_analysis(stacks, total, top_n),
        'bottom_up': bottom_up_analysis(stacks, total, top_n),
        'framework_hotspots': frame_pattern_analysis(stacks, total, common_patterns, top_n)
    }

    # 如果检测到特定语言，添加语言特定分析
    if detected_lang and detected_lang in LANGUAGE_PATTERNS:
        suffix = LANGUAGE_PATTERNS[detected_lang]['suffix']
        result[f'{detected_lang}_frames'] = language_frame_analysis(stacks, total, suffix, top_n)

    json_output = json.dumps(result, indent=2)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(json_output)
        print(f'Hotspot analysis saved to: {output_file}')

    if '--json' in sys.argv:
        print(json_output)
    else:
        print("=" * 80)
        print(f"Hotspot Analysis - Total Samples: {total}, Unique Stacks: {len(stacks)}")
        print(f"Detected Language: {detected_lang or 'Unknown'}")
        print("=" * 80)
        print("\n### Top-Down Analysis (by root frame)")
        print(f"{'Rank':<6} {'Frame':<40} {'Count':<10} {'Percent':<10}")
        print("-" * 70)
        for item in result['top_down']:
            print(f"{item['rank']:<6} {item['frame'][:40]:<40} {item['count']:<10} {item['percent']:.2f}%")

        print("\n### Bottom-Up Analysis (by leaf frame)")
        print(f"{'Rank':<6} {'Leaf':<40} {'Count':<10} {'Percent':<10}")
        print("-" * 70)
        for item in result['bottom_up']:
            print(f"{item['rank']:<6} {item['frame'][:40]:<40} {item['count']:<10} {item['percent']:.2f}%")

        if detected_lang:
            lang_frames = result.get(f'{detected_lang}_frames', [])
            print(f"\n### {detected_lang.capitalize()} Frames Analysis")
            print(f"{'Rank':<6} {'Frame':<60} {'Percent':<10}")
            print("-" * 80)
            for item in lang_frames:
                print(f"{item['rank']:<6} {item['frame'][:60]:<60} {item['percent']:.2f}%")

        print("\n### Framework Hotspots")
        print(f"{'Rank':<6} {'Frame':<60} {'Percent':<10}")
        print("-" * 80)
        for item in result['framework_hotspots']:
            print(f"{item['rank']:<6} {item['frame'][:60]:<60} {item['percent']:.2f}%")

if __name__ == '__main__':
    main()
