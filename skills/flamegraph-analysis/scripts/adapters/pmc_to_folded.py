#!/usr/bin/env python3
# =============================================================================
# 脚本：pmc_to_folded.py
# 用途：将 FreeBSD pmcstat -G 输出转换为 folded 格式
# 使用：python3 pmc_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（pmcstat 输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：使用 'pmcstat -G -o pmcstat.out' 生成输入文件
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def pmc_to_folded(content: str) -> str:
    """
    将 FreeBSD pmcstat -G 输出转换为 folded 格式
    
    pmcstat 输出格式示例:
    1 0 0 0x80106f0c0 0x80106f0c0 1 0 0 0 0 0 0 0x80106f0c0 0x80106f0c0
    1 0 0 0x80106f0d0 0x80106f0d0 1 0 0 0 0 0 0 0x80106f0d0 0x80106f0d0
    ...
    END
    0x80106f0c0 0 0 0 0x800822b60 0x800822b60 1 0x0 0 0 0 0x800822b60 0x800822b60 0x800822b60
    ...
    
    转换为:
    function1;function2;function3 1
    """
    collapsed = defaultdict(int)
    current_stack = []

    for line in content.split('\n'):
        stripped = line.strip()
        
        if not stripped or stripped.startswith('#'):
            continue
        
        # 检测 END 标记，切换到符号解析模式
        if stripped == 'END':
            current_stack = []
            continue
        
        # 解析堆栈行
        parts = stripped.split()
        if len(parts) >= 13:
            # 格式: pid tid cpu pc ...
            pc = parts[3]
            if pc.startswith('0x'):
                current_stack.insert(0, pc)
        
        # 尝试匹配计数行
        count_match = re.match(r'^\s*(\d+)\s*$', stripped)
        if count_match and current_stack:
            collapsed[';'.join(current_stack)] += int(count_match.group(1))
            current_stack = []

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 FreeBSD pmcstat -G 输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 pmc_to_folded.py --input pmcstat.out --output out.folded
  pmcstat -G -o pmcstat.out
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（pmcstat 输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = pmc_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()