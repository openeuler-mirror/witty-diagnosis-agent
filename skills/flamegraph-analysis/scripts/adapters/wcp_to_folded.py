#!/usr/bin/env python3
# =============================================================================
# 脚本：wcp_to_folded.py
# 用途：将 wallClockProfiler 输出转换为 folded 格式
# 使用：python3 wcp_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（wallClockProfiler 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def wcp_to_folded(content: str) -> str:
    """
    将 wallClockProfiler 输出转换为 folded 格式
    
    wallClockProfiler 输出格式示例:
    Thread 1234:
        0x1234567890abcdef  MyApp!SomeFunction
        0xabcdef1234567890  MyApp!AnotherFunction
        0xdeadbeef00000000  ntdll!NtWaitForSingleObject
    Count: 42
    
    转换为:
    ntdll!NtWaitForSingleObject;MyApp!AnotherFunction;MyApp!SomeFunction 42
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        # 检测新线程开始
        if stripped.startswith('Thread'):
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            continue
        
        # 匹配计数行
        count_match = re.match(r'Count:\s*(\d+)', stripped)
        if count_match and current_stack:
            collapsed[';'.join(current_stack)] += int(count_match.group(1))
            current_stack = []
            continue
        
        # 匹配堆栈行
        match = re.match(r'0x[0-9a-fA-F]+\s+(.+)', stripped)
        if match:
            func = match.group(1).strip()
            current_stack.insert(0, func)
            continue
        
        # 空行，结束当前堆栈
        if not stripped and current_stack:
            collapsed[';'.join(current_stack)] += 1
            current_stack = []

    # 处理最后一个堆栈
    if current_stack:
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 wallClockProfiler 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 wcp_to_folded.py --input wcp.out --output out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（wallClockProfiler 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = wcp_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()