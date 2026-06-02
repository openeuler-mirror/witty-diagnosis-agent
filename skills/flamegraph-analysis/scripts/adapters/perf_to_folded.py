#!/usr/bin/env python3
# =============================================================================
# 脚本：perf_to_folded.py
# 用途：将 Linux perf script 输出转换为 folded 格式（与 stackcollapse-perf.pl 保持一致）
# 使用：python3 perf_to_folded.py [--input FILE] [--output FILE] [--all]
# 参数：
#   --input FILE     : 指定输入文件（perf script 输出）
#   --output FILE    : 指定输出文件（folded 格式）
#   --pid            : 在进程名中包含 PID
#   --tid            : 在进程名中包含 TID 和 PID
#   --kernel         : 给内核函数添加 _[k] 注解
#   --jit            : 给 JIT 函数添加 _[j] 注解
#   --inline         : 给内联函数添加 _[i] 注解
#   --all            : 启用所有注解（--kernel --jit --inline）
#   --addrs          : 未知符号包含原始地址
#   --event-filter   : 事件类型过滤（如 cycles、cpu-clock）
#   --help / -h      : 显示帮助信息
# 说明：与 stackcollapse-perf.pl 行为保持一致
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict

JAVA_PACKAGE_PREFIXES = (
    'java/', 'javax/', 'jdk/', 'net/', 'org/', 'com/', 'io/', 'sun/',
    'Lorg/', 'Lcom/', 'Lio/', 'Lnet/', 'Ljavax/', 'Ljdk/', 'Lsun/',
)


def is_java_frame(func: str) -> bool:
    return func.startswith(JAVA_PACKAGE_PREFIXES) or '/gen/' in func


def tidy_generic(func: str) -> str:
    if ';' in func:
        func = func.replace(';', ':')
    if not re.search(r'\.\(.*\)\.', func):
        func = re.sub(r'\(.*', '', func)
    func = re.sub(r'\s+', '_', func)
    func = func.strip()
    return func


def tidy_java(func: str) -> str:
    if func.startswith('L') and '/' in func:
        func = func[1:]
    return func


def normalize_frame(func: str, pname: str = '', annotate_kernel: bool = False,
                    annotate_jit: bool = False, annotate_inline: bool = False,
                    module: str = '', include_addrs: bool = False, pc: str = '',
                    is_inline: bool = False) -> str:
    func = tidy_generic(func)
    if pname == 'java' or is_java_frame(func):
        func = tidy_java(func)

    # 内联标记处理
    if is_inline and annotate_inline:
        func += '_[i]'
    
    # 内核标记处理
    is_kernel = False
    if annotate_kernel and module:
        if re.search(r'(\[k\]|vmlinux|kernel|^sys_|^do_|^__do_|^__)', module):
            is_kernel = True
        elif re.search(r'(\[k\]|vmlinux|kernel)', func):
            is_kernel = True
    
    # JIT 标记处理
    is_jit = False
    if annotate_jit and module and re.search(r'/tmp/perf-\d+\.map', module):
        is_jit = True
    
    # 添加标记（按 stackcollapse-perf.pl 顺序：先内核/JIT，再内联）
    if is_kernel and not func.endswith('_k]'):
        func += '_[k]'
    elif is_jit and not func.endswith('_j]'):
        func += '_[j]'

    if include_addrs and pc:
        func = f'[{func} <{pc}>]'

    return func


def perf_to_folded(content: str, include_pname: bool = True,
                   include_pid: bool = False, include_tid: bool = False,
                   annotate_kernel: bool = False, annotate_jit: bool = False,
                   annotate_inline: bool = False, include_addrs: bool = False,
                   event_filter: str = '') -> str:
    collapsed = defaultdict(int)
    current_stack = []
    in_stack = False
    pname = ''
    m_pid = ''
    m_tid = ''
    m_period = 1

    for line in content.split('\n'):
        stripped = line.rstrip()

        if not stripped:
            if current_stack:
                if include_pname and pname:
                    current_stack.append(pname)
                if current_stack:
                    # 按 stackcollapse-perf.pl：内核到用户的顺序
                    collapsed[';'.join(current_stack)] += m_period
                current_stack = []
                in_stack = False
            continue

        if stripped.startswith('#'):
            continue

        # 支持各种 perf script 格式（参考 stackcollapse-perf.pl 的方案）
        # 两步匹配：先匹配开头的 comm/pid/tid，再匹配结尾的 period/event
        event_match = re.match(r'^(\S.+?)\s+(\d+)(?:/(\d+))?\s+', stripped)
        if event_match:
            comm = event_match.group(1)
            pid = event_match.group(2)
            tid = event_match.group(3)
            period_str = None
            event = None
            
            # 匹配结尾部分：": <period> <event>:"
            # period 可以是整数或浮点数（参考 stackcollapse-perf.pl 的做法）
            end_match = re.search(r':\s*([\d.]+)*\s*(\S+):\s*$', stripped)
            if end_match:
                period_str = end_match.group(1)
                event = end_match.group(2)
            else:
                # 没有 period，直接匹配 ": <event>:"
                end_match = re.search(r':\s*(\S+):\s*$', stripped)
                if end_match:
                    event = end_match.group(1)
            
            if current_stack:
                if include_pname and pname:
                    current_stack.append(pname)
                if current_stack:
                    collapsed[';'.join(current_stack)] += m_period
                current_stack = []
            
            in_stack = True
            tid = tid or pid

            if event_filter and event != event_filter:
                current_stack = []
                in_stack = False
                continue

            m_period = 1
            if period_str:
                try:
                    m_period = int(float(period_str))
                except ValueError:
                    m_period = 1

            m_pid = pid
            m_tid = tid

            if include_tid:
                pname = f"{comm}-{m_pid}/{m_tid}"
            elif include_pid:
                pname = f"{comm}-{m_pid}"
            else:
                pname = comm
            pname = pname.replace(' ', '_')
            continue

        if in_stack:
            # 匹配：地址 符号+偏移 (模块)
            addr_match = re.match(
                r'^\s*([0-9a-fA-F]+)\s+(\S+?)(?:\+0x[0-9a-fA-F]+)?(?:\s+\(([^)]+)\))?$',
                stripped
            )
            if addr_match:
                pc, symbol, module = addr_match.group(1), addr_match.group(2), addr_match.group(3)
                
                # 处理 inline 函数（用 -> 分隔）
                inline_parts = symbol.split('->')
                
                for idx, part in enumerate(inline_parts):
                    func = part
                    
                    # 去除偏移
                    func = re.sub(r'\+0x[\da-fA-F]+$', '', func)
                    
                    # 跳过无效符号
                    if not func or func.startswith('('):
                        continue
                        
                    # 处理未知符号
                    if func in ('unknown', '[unknown]', '???'):
                        if module and module != '[unknown]':
                            func = re.sub(r'.*/', '', module)
                        else:
                            func = 'unknown'
                        if include_addrs:
                            func = f'[{func} <{pc}>]'
                    
                    # 规范化帧
                    is_inline_frame = (idx > 0) or (len(inline_parts) > 1)
                    func = normalize_frame(
                        func, pname, annotate_kernel, annotate_jit,
                        annotate_inline, module or '', include_addrs, pc,
                        is_inline=is_inline_frame
                    )
                    
                    # 按 stackcollapse-perf.pl：内核到用户顺序（push to front）
                    current_stack.insert(0, func)
                
                # 添加模块信息（如果存在且不是内核/JIT）
                if module and module not in ('[unknown]', 'unknown'):
                    # 检查是否已经在函数名中
                    module_clean = re.sub(r'.*/', '', module)
                    if not any(module_clean in f for f in current_stack[:3]):
                        # 对于共享库，添加模块信息
                        if re.search(r'\.so(\.[0-9]+)?$', module):
                            current_stack.insert(0, f'[{module_clean}]')
                            
            elif 'unknown' not in stripped.lower() and not stripped.startswith('['):
                parts = stripped.split()
                if len(parts) >= 2:
                    addr, symbol = parts[0], parts[1]
                    if re.match(r'^[0-9a-fA-F]+$', addr) and symbol not in ('unknown', '???'):
                        symbol = normalize_frame(symbol, pname, annotate_kernel, annotate_jit)
                        if len(parts) >= 3 and parts[2].startswith('('):
                            module = parts[2].strip('()')
                            symbol = f"{symbol} ({module})"
                        current_stack.insert(0, symbol)

    if current_stack:
        if include_pname and pname:
            current_stack.append(pname)
        if current_stack:
            collapsed[';'.join(current_stack)] += m_period

    # 按调用栈长度排序（与 stackcollapse-perf.pl 一致）
    folded_lines = [f"{stack} {count}" for stack, count in sorted(collapsed.items())]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 perf script 输出转换为 folded 格式（与 stackcollapse-perf.pl 保持一致）',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 perf_to_folded.py --input out.perf --output out.folded
  python3 perf_to_folded.py --input out.perf --all
  cat out.perf | python3 perf_to_folded.py > out.folded

perf script 必须包含堆栈信息。如果缺少堆栈，请尝试:
  perf script -f comm,pid,tid,cpu,time,event,ip,sym,dso,trace | python3 perf_to_folded.py

与 stackcollapse-perf.pl 行为保持一致：
- 栈帧顺序：内核态 -> 用户态（自底向上）
- 默认不添加标记，使用 --all 参数启用所有注解
- 包含库模块信息（如 [libpthread-2.19.so]）
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（perf script 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')
    parser.add_argument('--pid', action='store_true', help='在进程名中包含 PID')
    parser.add_argument('--tid', action='store_true', help='在进程名中包含 TID 和 PID')
    parser.add_argument('--kernel', action='store_true', help='给内核函数添加 _[k] 注解')
    parser.add_argument('--jit', action='store_true', help='给 JIT 函数添加 _[j] 注解')
    parser.add_argument('--inline', action='store_true', help='给内联函数添加 _[i] 注解')
    parser.add_argument('--all', action='store_true', help='启用所有注解（--kernel --jit --inline）')
    parser.add_argument('--addrs', action='store_true', help='未知符号包含原始地址')
    parser.add_argument('--event-filter', type=str, default='',
                        help='事件类型过滤（如 cycles、cpu-clock）')

    args = parser.parse_args()

    # 读取内容
    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    # --all 启用所有注解
    annotate_kernel = args.kernel or args.all
    annotate_jit = args.jit or args.all
    annotate_inline = args.inline or args.all

    folded = perf_to_folded(
        content,
        include_pname=True,
        include_pid=args.pid,
        include_tid=args.tid,
        annotate_kernel=annotate_kernel,
        annotate_jit=annotate_jit,
        annotate_inline=annotate_inline,
        include_addrs=args.addrs,
        event_filter=args.event_filter or ''
    )

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()
