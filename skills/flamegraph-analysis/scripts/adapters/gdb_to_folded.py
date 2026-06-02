#!/usr/bin/env python3
# =============================================================================
# 脚本：gdb_to_folded.py
# 用途：将 gdb 堆栈输出转换为 folded 格式
# 使用：python3 gdb_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（gdb 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：在 gdb 中使用 'thread apply all bt' 生成堆栈
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def gdb_to_folded(content: str) -> str:
    """
    将 gdb 堆栈输出转换为 folded 格式
    
    gdb 输出格式示例:
    #0  0x00007f8b3c001234 in native_safe_halt () at kernel.c:123
    #1  0x00007f8b3c005678 in default_idle () at kernel.c:456
    #2  0x00007f8b3c009abc in cpu_idle () at kernel.c:789
    (gdb)
    
    转换为:
    cpu_idle;default_idle;native_safe_halt 1
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        # 检测新的堆栈开始（(gdb) 提示符）
        if stripped.startswith('(gdb)'):
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            continue
        
        # 匹配堆栈行
        match = re.match(r'#\d+\s+0x[0-9a-fA-F]+\s+in\s+([^(]+)', stripped)
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
        description='将 gdb 堆栈输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 gdb_to_folded.py --input gdb.out --output out.folded
  
  在 gdb 中生成堆栈:
  (gdb) thread apply all bt
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（gdb 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = gdb_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()