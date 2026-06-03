#!/usr/bin/env python3
# =============================================================================
# 脚本：java_exceptions_to_folded.py
# 用途：将 Java 异常堆栈输出转换为 folded 格式
# 使用：python3 java_exceptions_to_folded.py [--input FILE] [--output FILE]
# 参数：
#   --input FILE   : 输入文件（Java 异常输出）
#   --output FILE  : 输出文件（folded 格式）
#   --help / -h    : 显示帮助信息
# =============================================================================
import sys
import re
import argparse
from collections import defaultdict


def java_exceptions_to_folded(content: str) -> str:
    """
    将 Java 异常堆栈输出转换为 folded 格式
    
    Java 异常输出格式示例:
    Exception in thread "main" java.lang.NullPointerException
        at com.example.Class.method(Class.java:123)
        at com.example.Class.main(Class.java:45)
    
    转换为:
    com.example.Class.main;com.example.Class.method 1
    """
    collapsed = defaultdict(int)
    current_stack = []
    in_exception = False

    for line in content.split('\n'):
        stripped = line.strip()
        
        # 检测异常开始
        if 'Exception' in stripped or 'Error' in stripped:
            if current_stack:
                collapsed[';'.join(current_stack)] += 1
                current_stack = []
            in_exception = True
            continue
        
        # 在异常中，匹配堆栈行
        if in_exception and stripped.startswith('at '):
            match = re.match(r'^\s*at ([^(]+)', stripped)
            if match:
                func = match.group(1).strip()
                current_stack.insert(0, func)
            continue
        
        # 空行或其他内容，结束当前异常
        if not stripped and in_exception and current_stack:
            collapsed[';'.join(current_stack)] += 1
            current_stack = []
            in_exception = False

    # 处理最后一个异常
    if current_stack:
        collapsed[';'.join(current_stack)] += 1

    folded_lines = [f"{stack} {count}" for stack, count in collapsed.items()]
    return '\n'.join(folded_lines)


def main():
    parser = argparse.ArgumentParser(
        description='将 Java 异常堆栈输出转换为 folded 格式',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  python3 java_exceptions_to_folded.py --input exceptions.out --output out.folded
        """
    )
    parser.add_argument('--input', '-i', help='输入文件（Java 异常输出）')
    parser.add_argument('--output', '-o', help='输出文件（folded 格式）')

    args = parser.parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    folded = java_exceptions_to_folded(content)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(folded)
    else:
        print(folded)


if __name__ == '__main__':
    main()