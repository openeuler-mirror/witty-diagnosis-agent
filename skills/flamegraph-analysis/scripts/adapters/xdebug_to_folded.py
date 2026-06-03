#!/usr/bin/env python3
# =============================================================================
# 脚本：xdebug_to_folded.py
# 用途：将 PHP Xdebug 输出转换为 folded 格式
# 使用：python3 xdebug_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（Xdebug 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def xdebug_to_folded(content: str) -> str:
    """
    将 PHP Xdebug 输出转换为 folded 格式
    
    Xdebug 输出格式示例:
    0.000000 12345 1
    0.000010 12345 2
    0.000020 12345 3
    ...
    
    或类似的格式，包含时间戳、进程ID和堆栈深度
    
    转换为:
    func3;func2;func1 1
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        if not stripped:
            continue
        
        # Xdebug trace 格式: timestamp, pid, depth, function, file, line
        parts = stripped.split('\t')
        if len(parts) >= 4:
            try:
                depth = int(parts[2])
                func = parts[3]
                
                # 清理函数名
                func = re.sub(r'\(.*\)', '', func).strip()
                
                # 维护堆栈
                while len(current_stack) > depth:
                    current_stack.pop()
                
                if depth >= len(current_stack):
                    current_stack.append(func)
                
            except (ValueError, IndexError):
                continue
        
        # 简单格式：每行一个函数名
        elif not re.match(r'^\d', stripped):
            current_stack.insert(0, stripped)
    
    # 只记录完整的堆栈（最深的那个）
    if current_stack:
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 PHP Xdebug 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 xdebug_to_folded.py --input xdebug.out --output out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（Xdebug 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = xdebug_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()