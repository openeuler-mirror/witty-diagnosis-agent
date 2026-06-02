#!/usr/bin/env python3
# =============================================================================
# 脚本：faulthandler_to_folded.py
# 用途：将 Python faulthandler 输出转换为 folded 格式
# 使用：python3 faulthandler_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（faulthandler 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：在 Python 代码中启用 faulthandler:
#       import faulthandler
#       faulthandler.dump_traceback_later(10, repeat=True, file=open('traceback.out', 'w'))
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def faulthandler_to_folded(content: str) -> str:
    """
    将 Python faulthandler 输出转换为 folded 格式
    
    faulthandler 输出格式示例:
    Thread 0x00007f8b3bfff700 (most recent call first):
      File "/path/to/file.py", line 123 in function_name
      File "/path/to/file2.py", line 45 in another_func
    
    转换为:
    /path/to/file.py:123:function_name;/path/to/file2.py:45:another_func 1
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
        
        # 匹配堆栈行
        match = re.match(r'File "([^"]+)", line (\d+) in (\S+)', stripped)
        if match:
            filename = match.group(1)
            line_num = match.group(2)
            function = match.group(3)
            frame = f"{filename}:{line_num}:{function}"
            current_stack.insert(0, frame)
            continue
        
        # 空行或其他内容，结束当前堆栈
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
        description='将 Python faulthandler 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 faulthandler_to_folded.py --input traceback.out --output out.folded
  
  在 Python 代码中启用 faulthandler:
  import faulthandler
  faulthandler.dump_traceback_later(10, repeat=True, file=open('traceback.out', 'w'))
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（faulthandler 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = faulthandler_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()