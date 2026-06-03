#!/usr/bin/env python3
# =============================================================================
# 脚本：bcc_to_folded.py
# 用途：将 BCC/eBPF 输出转换为 folded 格式
# 使用：python3 bcc_to_folded.py [input_file]
# 参数：
#   input_file : BCC 输出文件（可选，默认从 stdin 读取）
# 说明：支持 BCC tools（如 profile、trace 等）的输出格式
# =============================================================================
import sys
from collections import defaultdict

def bcc_to_folded(content: str) -> str:
    folded_stacks = []
    current_stack = []
    current_count = 1

    for line in content.split('\n'):
        line = line.strip()
        if not line:
            continue

        if line.isdigit() or (line.startswith('-') and line[1:].isdigit()):
            if current_stack:
                folded_stacks.append(';'.join(reversed(current_stack)) + ' ' + str(current_count))
                current_stack = []
            if line.isdigit():
                current_count = int(line)
            continue

        if ';' in line:
            frames = [f.strip() for f in line.split(';') if f.strip()]
            if frames:
                current_stack = frames

    if current_stack:
        folded_stacks.append(';'.join(reversed(current_stack)) + ' ' + str(current_count))

    return '\n'.join(folded_stacks)

def main():
    if len(sys.argv) < 2:
        input_file = sys.stdin
    else:
        input_file = open(sys.argv[1], 'r', encoding='utf-8', errors='replace')

    content = input_file.read()
    folded = bcc_to_folded(content)
    print(folded)

if __name__ == '__main__':
    main()
