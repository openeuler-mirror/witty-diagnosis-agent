#!/usr/bin/env python3
# =============================================================================
# 脚本：recursive_fold.py
# 用途：后处理折叠格式，合并直接递归调用
# 使用：python3 recursive_fold.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（folded 格式）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# 说明：例如 main;recursive;recursive;recursive;helper 1 转换为 main;recursive;helper 1
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def recursive_fold(content: str) -> str:
    """
    后处理折叠格式，合并直接递归调用
    
    输入示例:
    main;recursive;recursive;recursive;helper 1
    
    输出示例:
    main;recursive;helper 1
    """
    collapsed = defaultdict(int)

    for line in content.split('\n'):
        stripped = line.strip()
        
        if not stripped:
            continue
        
        # 解析 folded 格式
        match = re.match(r'^(.*)\s+(\d+(?:\.\d*)?)$', stripped)
        if match:
            stack_str = match.group(1)
            count = float(match.group(2))
            
            # 拆分堆栈
            parts = stack_str.split(';')
            
            # 移除连续重复的函数
            result = []
            last = ""
            for part in parts:
                if part != last:
                    result.append(part)
                    last = part
            
            # 重新组合
            collapsed[';'.join(result)] += count

    folded_lines = [f"{stack} {int(count) if count.is_integer() else count}" 
                   for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='后处理折叠格式，合并直接递归调用',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 recursive_fold.py --input in.folded --output out.folded
  cat in.folded | python3 recursive_fold.py > out.folded
  
  输入:
    main;recursive;recursive;recursive;helper 1
  
  输出:
    main;recursive;helper 1
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（folded 格式）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = recursive_fold(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()