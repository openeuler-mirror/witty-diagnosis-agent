#!/usr/bin/env python3
# =============================================================================
# 脚本：ljp_to_folded.py
# 用途：将 Lightweight Java Profiler 输出转换为 folded 格式
# 使用：python3 ljp_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（LJP 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def ljp_to_folded(content: str) -> str:
    """
    将 Lightweight Java Profiler 输出转换为 folded 格式
    
    LJP 输出格式示例:
    3
    java.lang.Thread.run
    java.util.concurrent.ThreadPoolExecutor$Worker.run
    java.util.concurrent.ThreadPoolExecutor.runWorker
    1
    ...
    
    转换为:
    java.lang.Thread.run;java.util.concurrent.ThreadPoolExecutor$Worker.run;java.util.concurrent.ThreadPoolExecutor.runWorker 3
    """
    collapsed = defaultdict(int)
    current_stack = []
    current_count = 1

    for line in content.split('\n'):
        stripped = line.strip()
        
        if not stripped:
            continue
        
        # 尝试匹配计数值
        if stripped.isdigit():
            # 如果之前有堆栈，先记录
            if current_stack:
                collapsed[';'.join(current_stack)] += current_count
            # 设置新的计数值
            current_count = int(stripped)
            current_stack = []
            continue
        
        # 这是一个函数名
        current_stack.insert(0, stripped)

    # 处理最后一个堆栈
    if current_stack:
        collapsed[';'.join(current_stack)] += current_count

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 Lightweight Java Profiler 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 ljp_to_folded.py --input ljp.out --output out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（LJP 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = ljp_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()