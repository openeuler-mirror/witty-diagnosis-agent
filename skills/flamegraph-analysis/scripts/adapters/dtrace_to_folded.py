#!/usr/bin/env python3
# =============================================================================
# 脚本：dtrace_to_folded.py
# 用途：将 DTrace 堆栈输出转换为 folded 格式
# 使用：python3 dtrace_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE        : 输入文件（DTrace 堆栈输出）
#   --output FILE       : 输出文件（folded 格式）
#   --header-lines N    : 跳过的文件头行数（默认: 3）
#   --include-offset    : 保留函数偏移地址
#   --annotate-inline   : 给内联函数添加 _[i] 注解
#   --help / -h         : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def tidy_cpp_func(func: str) -> str:
    func = re.sub(r'(::.*)[(<].*', r'\1', func)
    return func


def tidy_java_func(func: str) -> str:
    func = func.replace(';', ':')
    func = re.sub(r'^L', '', func)
    return func


def dtrace_to_folded(content: str, header_lines: int = 3,
                     include_offset: bool = False,
                     annotate_inline: bool = False) -> str:
    collapsed = defaultdict(int)
    current_stack = []
    nr = 0

    for line in content.split('\n'):
        nr += 1
        if nr <= header_lines:
            continue

        stripped = line.strip()

        if not stripped:
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            continue

        count_match = re.match(r'^\s*(\d+)\s*$', stripped)
        if count_match:
            count = int(count_match.group(1))
            if current_stack:
                collapsed[';'.join(current_stack)] += count
                current_stack = []
            continue

        if '`' in stripped:
            parts = stripped.split('`')
            if len(parts) >= 2:
                frame = parts[-1]
                if not include_offset:
                    frame = frame.split('+')[0]

                if frame and not frame.startswith('-'):
                    frame = tidy_cpp_func(frame)
                    frame = tidy_java_func(frame)

                    if frame == '':
                        frame = '-'

                    inline_frames = []
                    for sub in frame.split('->'):
                        sub = sub.strip()
                        if sub:
                            if annotate_inline and len(inline_frames) > 0:
                                sub += '_[i]'
                            inline_frames.append(sub)

                    current_stack[0:0] = inline_frames

    if current_stack:
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 DTrace 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 dtrace_to_folded.py --input out.stacks --output out.folded
  cat out.stacks | python3 dtrace_to_folded.py > out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（DTrace 堆栈输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')
    parser.add_argument('--header-lines', type=int, default=3,
                        help='跳过的文件头行数（默认: 3）')
    parser.add_argument('--include-offset', action='store_true',
                        help='保留函数偏移地址')
    parser.add_argument('--annotate-inline', action='store_true',
                        help='给内联函数添加 _[i] 注解')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = dtrace_to_folded(
        content,
        header_lines=args.header_lines,
        include_offset=args.include_offset,
        annotate_inline=args.annotate_inline
    )

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()
