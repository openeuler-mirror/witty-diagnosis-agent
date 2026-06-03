#!/usr/bin/env python3
# =============================================================================
# 脚本：stap_to_folded.py
# 用途：将 SystemTap 输出转换为 folded 格式
# 使用：python3 stap_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（SystemTap 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：使用 'stap -e "probe timer.profile { @[stack()] = count(); }" -o stap.out' 生成输入
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def stap_to_folded(content: str) -> str:
    """
    将 SystemTap 输出转换为 folded 格式
    
    SystemTap 输出格式示例:
      0xffffffff8103ce3b : native_safe_halt+0xb/0x10 [kernel]
      0xffffffff8101c6a3 : default_idle+0x53/0x1d0 [kernel]
          2404
    
    转换为:
    start_kernel;rest_init;cpu_idle;default_idle;native_safe_halt 2404
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        # 匹配计数行（纯数字）
        if stripped.isdigit():
            if current_stack:
                collapsed[';'.join(current_stack)] += int(stripped)
                current_stack = []
            continue
        
        if not stripped:
            continue
        
        # 匹配堆栈行: 地址 : 函数名+偏移 [模块]
        match = re.match(r'0x[0-9a-fA-F]+\s*:\s*([^+]+)', stripped)
        if match:
            func = match.group(1).strip()
            # 移除尾部的 +offset
            func = re.sub(r'\+[^+]*$', '', func)
            if func:
                current_stack.insert(0, func)
            continue
        
        # 尝试其他格式
        parts = stripped.split(':')
        if len(parts) >= 2:
            func_part = parts[-1].strip()
            func = re.sub(r'\+[^+]*$', '', func_part)
            func = func.split()[0] if func else '-'
            current_stack.insert(0, func)

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 SystemTap 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 stap_to_folded.py --input stap.out --output out.folded
  stap -e 'probe timer.profile { @[stack()] = count(); }' -o stap.out
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（SystemTap 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = stap_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()