#!/usr/bin/env python3
# =============================================================================
# 脚本：vtune_to_folded.py
# 用途：将 Intel VTune 输出转换为 folded 格式
# 使用：python3 vtune_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE        : 输入文件（VTune 输出）
#   --output FILE       : 输出文件（folded 格式）
#   --annotate-module   : 在函数名后标注模块名
#   --help / -h         : 显示帮助信息
# 说明：参考 FlameGraph 的 stackcollapse-vtune.pl 实现
#       使用示例: vtune -collect hotspots -result-dir r001hs -report stdout | python3 vtune_to_folded.py > out.folded
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def vtune_to_folded(content: str, annotate_module: bool = False) -> str:
    """
    将 VTune 输出转换为 folded 格式
    
    VTune 输出格式示例:
    CPU: Intel(R) Xeon(R) CPU E5-2699 v4 @ 2.20GHz, 22 cores
    Timestamp: 00:00:00.000
    Process ID: 12345
    Thread ID: 12346
    Module: libc-2.31.so
    Function: malloc
    Stack trace:
        malloc
        __libc_calloc
        _int_malloc
        ...
    """
    collapsed = defaultdict(int)
    current_stack = []
    in_stack = False
    module_name = ""

    for line in content.split('\n'):
        line = line.strip()
        
        if not line:
            if in_stack and current_stack:
                collapsed[';'.join(reversed(current_stack))] += 1
                current_stack = []
                in_stack = False
            continue
        
        # 检测模块信息
        module_match = re.match(r'^Module:\s*(.+)$', line)
        if module_match:
            module_name = module_match.group(1).strip()
            continue
        
        # 检测函数信息
        func_match = re.match(r'^Function:\s*(.+)$', line)
        if func_match:
            func = func_match.group(1).strip()
            # 清理函数名
            func = re.sub(r'\+0x[0-9a-fA-F]+$', '', func)
            func = re.sub(r'\s*\([^)]*\)$', '', func)
            
            if annotate_module and module_name:
                func = f"{func} [{module_name}]"
            
            current_stack.append(func)
            in_stack = True
            continue
        
        # 检测堆栈跟踪部分
        if line.startswith('Stack trace:'):
            in_stack = True
            continue
        
        # 堆栈帧（通常以缩进或地址开头）
        if in_stack:
            # 匹配函数名（可能包含地址偏移）
            frame_match = re.match(r'^\s*(?:0x[0-9a-fA-F]+\s+)?(.+?)(?:\s*\+0x[0-9a-fA-F]+)?\s*$', line)
            if frame_match:
                func = frame_match.group(1).strip()
                if func and func != '...':
                    func = re.sub(r'\s*\([^)]*\)$', '', func)
                    
                    if annotate_module and module_name:
                        func = f"{func} [{module_name}]"
                    
                    current_stack.append(func)
            continue
    
    # 处理最后一个堆栈
    if in_stack and current_stack:
        collapsed[';'.join(reversed(current_stack))] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 Intel VTune 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 vtune_to_folded.py --input vtune.out --output out.folded
  vtune -collect hotspots -result-dir r001hs -report stdout | python3 vtune_to_folded.py > out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（VTune 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')
    parser.add_argument('--annotate-module', '-m', action='store_true',
                        help='在函数名后标注模块名')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = vtune_to_folded(content, annotate_module=args.annotate_module)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()