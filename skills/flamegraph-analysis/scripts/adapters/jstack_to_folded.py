#!/usr/bin/env python3
# =============================================================================
# 脚本：jstack_to_folded.py
# 用途：将 Java jstack 输出转换为 folded 格式
# 使用：python3 jstack_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE      : 输入文件（jstack 输出）
#   --output FILE     : 输出文件（folded 格式）
#   --include-tname   : 在堆栈中包含线程名（默认启用）
#   --no-include-tname: 不包含线程名
#   --include-tid     : 在线程名中包含线程ID
#   --shorten-pkgs    : 缩短包名（如 java.lang.String -> j.l.String）
#   --help / -h       : 显示帮助信息
# 说明：需要至少采集100次 jstack 才能获得有意义的采样数据
#       i=0; while (( i++ < 100 )); do jstack PID >> out.jstacks; sleep 1; done
#       cat out.jstacks | python3 jstack_to_folded.py > out.folded
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def shorten_package_name(func: str) -> str:
    match = re.match(r'(.*\.)([^.]+\.[^.]+)$', func)
    if match:
        pkgs = match.group(1)
        cls_func = match.group(2)
        pkgs_short = re.sub(r'(\w)\w*', r'\1', pkgs)
        return pkgs_short + cls_func
    return func


def jstack_to_folded(content: str, include_tname: bool = True,
                     include_tid: bool = False,
                     shorten_pkgs: bool = False) -> str:
    collapsed = defaultdict(int)
    current_stack = []
    tname = None
    state = "?"

    BACKGROUND_THREADS = [
        'C. CompilerThread',
        'Signal Dispatcher',
        'Service Thread',
        'Attach Listener',
        'Finalizer',
        'Reference Handler'
    ]

    for line in content.split('\n'):
        stripped = line.strip()

        if not stripped:
            if state == "RUNNABLE" and current_stack:
                if tname and include_tname:
                    current_stack.insert(0, tname)
                collapsed[';'.join(current_stack)] += 1
            current_stack = []
            tname = None
            state = "?"
            continue

        if stripped.startswith('#'):
            continue

        thread_name_match = re.match(r'^"([^"]*)', stripped)
        if thread_name_match:
            name = thread_name_match.group(1)

            for bg in BACKGROUND_THREADS:
                if bg in name:
                    state = "BACKGROUND"
                    break

            if include_tname:
                tname = name
                if not include_tid:
                    tname = re.sub(r'-\d+$', '', tname)

        elif 'java.lang.Thread.State:' in stripped:
            state_match = re.search(r'java.lang.Thread.State: (\S+)', stripped)
            if state_match and state == "?":
                state = state_match.group(1)

        elif stripped.startswith('at '):
            func_match = re.match(r'^\s*at ([^(]*)', stripped)
            if func_match:
                func = func_match.group(1)

                if shorten_pkgs:
                    func = shorten_package_name(func)

                current_stack.insert(0, func)

                if 'epollWait' in func or 'EPoll.wait' in func:
                    state = "WAITING"
                elif 'socketAccept' in func or 'Socket.*accept0' in func or 'socketRead0' in func:
                    state = "NETWORK"

        elif stripped.startswith('- ') or stripped.startswith('20') or \
             stripped.startswith('Full thread dump') or \
             'JNI global references:' in stripped:
            continue

    if state == "RUNNABLE" and current_stack:
        if tname and include_tname:
            current_stack.insert(0, tname)
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 Java jstack 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 jstack_to_folded.py --input jstack.out --output out.folded
  jstack 12345 | python3 jstack_to_folded.py > out.folded
  
注意: 需要至少采集100次 jstack 才能获得有意义的采样数据
  i=0; while (( i++ < 100 )); do jstack PID >> out.jstacks; sleep 1; done
  cat out.jstacks | python3 jstack_to_folded.py > out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（jstack 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')
    parser.add_argument('--include-tname', action='store_true', default=True,
                        help='在堆栈中包含线程名（默认启用）')
    parser.add_argument('--no-include-tname', action='store_true',
                        help='不包含线程名')
    parser.add_argument('--include-tid', action='store_true',
                        help='在线程名中包含线程ID')
    parser.add_argument('--shorten-pkgs', action='store_true',
                        help='缩短包名（如 java.lang.String -> j.l.String）')

    args = parser.parse_args()

    include_tname = args.include_tname and not args.no_include_tname

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = jstack_to_folded(
        content,
        include_tname=include_tname,
        include_tid=args.include_tid,
        shorten_pkgs=args.shorten_pkgs
    )

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()
