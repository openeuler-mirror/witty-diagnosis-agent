#!/usr/bin/env python3
# =============================================================================
# 脚本：sample_to_folded.py
# 用途：将通用采样格式转换为 folded 格式
# 使用：python3 sample_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（采样输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def sample_to_folded(content: str) -> str:
    """
    将通用采样格式转换为 folded 格式
    
    通用采样格式示例:
    sample 1:
    func1
    func2
    func3
    
    sample 2:
    func1
    func4
    
    转换为:
    func3;func2;func1 1
    func4;func1 1
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        # 检测新采样开始
        if stripped.startswith('sample') or stripped.startswith('Sample'):
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            continue
        
        # 空行，结束当前堆栈
        if not stripped:
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            continue
        
        # 这是一个函数名
        current_stack.insert(0, stripped)

    # 处理最后一个堆栈
    if current_stack:
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将通用采样格式转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 sample_to_folded.py --input sample.out --output out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（采样输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = sample_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()