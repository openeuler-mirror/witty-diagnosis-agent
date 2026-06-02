#!/usr/bin/env python3
# =============================================================================
# 脚本：etw_to_folded.py
# 用途：将 Windows ETW CSV 输出转换为 folded 格式
# 使用：python3 etw_to_folded.py [input_file]
# 参数：
#   input_file : ETW CSV 文件（可选，默认从 stdin 读取）
# 说明：支持 Windows Performance Toolkit 导出的 CSV 格式
# =============================================================================
import sys
import csv
from collections import defaultdict

def etw_csv_to_folded(content: str) -> str:
    folded_stacks = defaultdict(int)

    lines = content.split('\n')
    if not lines:
        return ""

    reader = csv.DictReader(lines)
    stack_field = None

    for i, row in enumerate(reader):
        if i == 0:
            for key in row.keys():
                if 'stack' in key.lower() or 'callstack' in key.lower():
                    stack_field = key
                    break
            if not stack_field:
                for key in row.keys():
                    stack_field = key
                    break
            if not stack_field:
                continue

        stack_str = row.get(stack_field, '')
        if not stack_str:
            continue

        frames = [f.strip() for f in stack_str.split(';') if f.strip()]
        if frames:
            folded_stacks[';'.join(reversed(frames))] += 1

    folded_lines = [f"{stack} {count}" for stack, count in folded_stacks.items()]
    return '\n'.join(folded_lines)

def main():
    if len(sys.argv) < 2:
        input_file = sys.stdin
    else:
        input_file = open(sys.argv[1], 'r', encoding='utf-8', errors='replace')

    content = input_file.read()
    folded = etw_csv_to_folded(content)
    print(folded)

if __name__ == '__main__':
    main()
