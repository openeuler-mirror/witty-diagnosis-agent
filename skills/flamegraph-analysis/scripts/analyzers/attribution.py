#!/usr/bin/env python3
# =============================================================================
# 脚本：attribution.py
# 用途：代码归属分析（区分用户代码、库代码、系统代码、内核代码）
# 使用：python3 attribution.py <folded_file> [--input FILE] [--json] [--output FILE]
# 参数：
#   <folded_file>    : folded格式的调用栈文件（位置参数或--input指定）
#   --input FILE     : 指定输入文件
#   --json           : 输出JSON格式
#   --output FILE    : 将JSON结果保存到指定文件
#   --help / -h      : 显示帮助信息
# =============================================================================
import sys
import json
import re
from collections import defaultdict

USER_CODE_PATTERNS = [
    r'^/home/', r'^/Users/', r'^/src/', r'^/project/',
    r'^/workspace/', r'\.go$', r'\.java$', r'\.py$', r'\.rs$',
    r'^com/company/', r'^io/microscope/', r'^app/',
]

LIBRARY_PATTERNS = [
    r'node_modules/', r'venv/', r'\.so$', r'\.dll$', r'\.jar$',
    r'libpthread', r'libc\.', r'libjvm', r'libstdc++',
    r'golang.org/', r'google.golang.org/',
    r'npm/', r'pip/',
]

KERNEL_PATTERNS = [
    r'\.ko$', r'\[kernel\]', r'\[w\]', r'\[w:[0-9]+\]',
    r'^unix`', r'^sys_', r'^__GI_',
    r'\[kernel\.kallsyms\]', r'kallsyms',
]

RUNTIME_PATTERNS = [
    r'jvm\.so', r'libjvm', r'java\.lang\.', r'java\.util\.',
    r'org\.openjdk', r'sun\.misc',
    r'goruntime', r'runtime\.',
    r'v8.', r'node/',
    r'clr!', r'coreclr',
]

def classify_frame(frame: str):
    frame_lower = frame.lower()

    if any(re.search(p, frame_lower) for p in KERNEL_PATTERNS):
        return 'kernel'
    if any(re.search(p, frame_lower) for p in RUNTIME_PATTERNS):
        return 'runtime'
    if any(re.search(p, frame_lower) for p in LIBRARY_PATTERNS):
        return 'library'
    if any(re.search(p, frame_lower) for p in USER_CODE_PATTERNS):
        return 'user'
    if frame.startswith('[') or frame.startswith('<'):
        return 'unknown'
    return 'user'

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

def attribute(stacks, total):
    category_samples = defaultdict(int)
    category_frames = defaultdict(set)
    category_stacks = defaultdict(list)

    for stack, count in stacks:
        frames = stack.split(';')
        classified = [classify_frame(f) for f in frames]

        primary_category = max(set(classified), key=classified.count) if classified else 'unknown'

        category_samples[primary_category] += count
        category_frames[primary_category].update(frames)
        category_stacks[primary_category].append((stack, count))

    results = []
    for cat in ['user', 'library', 'runtime', 'kernel', 'unknown']:
        if category_samples[cat] > 0:
            pct = (category_samples[cat] / total * 100) if total > 0 else 0
            results.append({
                'category': cat,
                'samples': category_samples[cat],
                'percent': round(pct, 2),
                'unique_frames': len(category_frames[cat]),
                'sample_stacks': category_stacks[cat][:5]
            })

    results.sort(key=lambda x: -x['percent'])
    return results

def main():
    file_path = None
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""用途：代码归属分析（区分用户代码、库代码、系统代码、内核代码）

使用：python3 attribution.py <folded_file> [--input FILE] [--json] [--output FILE]

参数：
  <folded_file>    : folded格式的调用栈文件（位置参数）
  --input FILE     : 指定输入文件（可选）
  --json           : 输出JSON格式
  --output FILE    : 将JSON结果保存到指定文件
  --help / -h      : 显示此帮助信息

归属类别：
  user       : 用户代码（/home/、/src/、项目特定路径等）
  library    : 库代码（node_modules、.so、.jar等）
  system     : 系统代码（libc、pthread等系统库）
  kernel     : 内核代码（Linux内核函数）
  unknown    : 无法识别的代码
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
        print('使用：python3 attribution.py <folded_file> [--input FILE] [--json]')
        print('使用 --help 查看详细帮助')
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    stacks, total = parse_folded(content)
    attributions = attribute(stacks, total)

    result = {
        'total_samples': total,
        'attributions': attributions
    }

    json_output = json.dumps(result, indent=2)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(json_output)
        print(f'Attribution saved to: {output_file}')

    if '--json' in sys.argv:
        print(json_output)
    else:
        print("=" * 80)
        print(f"Attribution Analysis - Total Samples: {total}")
        print("=" * 80)
        print(f"\n{'Category':<15} {'Samples':<12} {'Percent':<10} {'Unique Frames'}")
        print("-" * 60)
        for a in result['attributions']:
            print(f"{a['category']:<15} {a['samples']:<12} {a['percent']:.2f}%      {a['unique_frames']}")

if __name__ == '__main__':
    main()
