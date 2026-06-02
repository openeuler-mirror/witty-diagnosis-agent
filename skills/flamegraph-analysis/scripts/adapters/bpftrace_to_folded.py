#!/usr/bin/env python3
# =============================================================================
# 脚本：bpftrace_to_folded.py
# 用途：将 bpftrace 输出转换为 folded 格式
# 使用：python3 bpftrace_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（bpftrace 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：使用 'bpftrace -e "profile:hz:99 { @[stack] = count(); }" | python3 bpftrace_to_folded.py > out.folded'
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def bpftrace_to_folded(content: str) -> str:
    """
    将 bpftrace 输出转换为 folded 格式
    
    bpftrace 输出格式示例:
    @[
    _raw_spin_lock_bh+0
    tcp_recvmsg+808
    inet_recvmsg+81
    ]: 3
    
    转换为:
    entry_SYSCALL_64_after_hwframe+61;do_syscall_64+115;sys_read+85 3
    """
    collapsed = defaultdict(int)
    current_stack = []
    in_stack = False

    for line in content.split('\n'):
        stripped = line.strip()
        
        if not in_stack:
            if stripped.startswith('@['):
                in_stack = True
            elif stripped.startswith('@[') and ',' in stripped:
                # 单行格式: @[, xxx]: count
                match = re.match(r'@\[\s*(.*)\]:\s*(\d+)', stripped)
                if match:
                    stack_str = match.group(1).strip()
                    count = int(match.group(2))
                    if stack_str:
                        collapsed[stack_str] += count
            continue
        
        # 在堆栈内部
        match = re.match(r',?\s?(.*)\]:\s*(\d+)', stripped)
        if match:
            func = match.group(1).strip()
            count = int(match.group(2))
            if func:
                current_stack.append(func)
            # 输出并重置
            if current_stack:
                collapsed[';'.join(reversed(current_stack))] += count
            current_stack = []
            in_stack = False
        elif stripped:
            current_stack.append(stripped)

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 bpftrace 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 bpftrace_to_folded.py --input bpftrace.out --output out.folded
  bpftrace -e 'profile:hz:99 { @[stack] = count(); }' | python3 bpftrace_to_folded.py > out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（bpftrace 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = bpftrace_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()