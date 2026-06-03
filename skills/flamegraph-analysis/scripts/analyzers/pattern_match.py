#!/usr/bin/env python3
# =============================================================================
# 脚本：pattern_match.py
# 用途：调用栈预处理（过滤分析工具自身调用栈）
# 使用：python3 pattern_match.py <folded_file> [--input FILE] [--json] [--output FILE]
# 参数：
#   <folded_file>    : folded格式的调用栈文件（位置参数或--input指定）
#   --input FILE     : 指定输入文件
#   --json           : 输出JSON格式
#   --output FILE    : 将JSON结果保存到指定文件
#   --help / -h      : 显示帮助信息
# =============================================================================
import sys
import json

# 分析工具自身的函数名（需要过滤，不应该归类为业务逻辑）
PROFILER_TOOLS = {'perf', 'perf_event', 'record', 'probe', 'ftrace', 'bpf'}


def parse_folded(content: str):
    """解析 folded 格式的调用栈数据"""
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


def extract_frame_name(frame: str) -> str:
    """从栈帧字符串中提取纯函数名，去掉模块信息"""
    idx = frame.rfind(' (')
    if idx > 0 and frame.endswith(')'):
        return frame[:idx]
    return frame


def classify_stack(stacks, min_weight=0.5):
    """
    简化版分类：只过滤 profiler 工具栈，所有有效栈都归为 application
    """
    category_matches = {
        'application': {'count': 0, 'samples': 0, 'stacks': [], 'frames': set()},
    }

    for stack, count in stacks:
        frames = stack.split(';')
        
        # 跳过 profiler 工具自身的调用栈（检查整个调用栈）
        if any(extract_frame_name(frame) in PROFILER_TOOLS for frame in frames):
            continue
        
        bottom_frame = frames[0] if frames else ''
        bottom_name = extract_frame_name(bottom_frame)
        
        # 所有有效栈都归为 application
        category_matches['application']['samples'] += count
        category_matches['application']['count'] += 1
        category_matches['application']['frames'].add(bottom_frame)
        category_matches['application']['stacks'].append((stack, count, bottom_frame, bottom_name, 1.0))

    return category_matches


def main():
    file_path = None
    output_file = None
    
    if '--help' in sys.argv or '-h' in sys.argv:
        print("""用途：调用栈预处理（过滤分析工具自身调用栈）

使用：python3 pattern_match.py <folded_file> [--input FILE] [--json] [--output FILE]

参数：
  <folded_file>    : folded格式的调用栈文件（位置参数）
  --input FILE     : 指定输入文件（可选）
  --json           : 输出JSON格式到stdout
  --output FILE    : 将JSON结果保存到指定文件
  --help / -h      : 显示此帮助信息

功能：
  - 过滤 perf/bpf/ftrace 等分析工具自身的调用栈
  - 将所有有效调用栈归为 application 类别
""")
        sys.exit(0)
    
    i = 1
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
        print('使用：python3 pattern_match.py <folded_file> [--input FILE] [--json]')
        print('使用 --help 查看详细帮助')
        sys.exit(1)

    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()

    stacks = parse_folded(content)
    total_samples = sum(c for _, c in stacks)
    matches = classify_stack(stacks)

    result = {
        'total_samples': total_samples,
        'categories': {}
    }

    for cat_name, cat_info in matches.items():
        if cat_info['samples'] > 0:
            pct = (cat_info['samples'] / total_samples * 100) if total_samples > 0 else 0
            if pct >= 0.1:
                result['categories'][cat_name] = {
                    'name': 'Application Logic',
                    'samples': cat_info['samples'],
                    'percent': round(pct, 2),
                    'frames': list(cat_info['frames'])[:20],
                    'stacks': [(s, c, f, p, w) for s, c, f, p, w in cat_info['stacks']][:10]
                }

    json_output = json.dumps(result, indent=2)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(json_output)
        print(f'Results saved to: {output_file}')

    if '--json' in sys.argv:
        print(json_output)
    else:
        print("=" * 80)
        print(f"Stack Preprocessing - Total Samples: {total_samples}")
        print("=" * 80)
        for cat_name, cat in result['categories'].items():
            print(f"\n### {cat['name']} ({cat_name})")
            print(f"Samples: {cat['samples']}, Percent: {cat['percent']:.2f}%")


if __name__ == '__main__':
    main()
