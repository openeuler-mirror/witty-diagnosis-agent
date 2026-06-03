#!/usr/bin/env python3
# =============================================================================
# 脚本：v8log_to_folded.py
# 用途：将 V8 日志格式转换为 folded 格式
# 使用：python3 v8log_to_folded.py [input_file]
# 参数：
#   input_file : V8 日志文件（可选，默认从 stdin 读取）
# 说明：支持 Node.js --log-code 和 --log-ticks 生成的日志格式
# =============================================================================
import sys
import re
from collections import defaultdict

def v8log_to_folded(content: str) -> str:
    code_map = {}
    ticks = []
    current_tick_stack = []
    current_tick_count = 0

    for line in content.split('\n'):
        line = line.strip()
        if not line:
            continue

        parts = line.split(',')
        tag = parts[0] if parts else ''

        if tag == 'code-creation':
            if len(parts) >= 8:
                addr = parts[3]
                func_name = parts[5]
                code_map[addr] = func_name

        elif tag == 'tick':
            if len(parts) >= 5:
                try:
                    tick_count = int(parts[4])
                except ValueError:
                    tick_count = 1

                stack_len = min(int(parts[4]) if parts[4].isdigit() else 0, len(parts) - 5)
                stack = []
                for i in range(stack_len):
                    addr_idx = 5 + i
                    if addr_idx < len(parts):
                        addr = parts[addr_idx]
                        func_name = code_map.get(addr, 'unknown')
                        if func_name and func_name not in ('0', '', '0x0'):
                            stack.append(func_name)

                if stack:
                    ticks.append((list(stack), tick_count))

    folded_map = defaultdict(int)
    for stack, count in ticks:
        folded_map[';'.join(reversed(stack))] += count

    folded_lines = [f"{stack} {count}" for stack, count in folded_map.items()]
    return '\n'.join(folded_lines)

def main():
    if len(sys.argv) < 2:
        input_file = sys.stdin
    else:
        input_file = open(sys.argv[1], 'r', encoding='utf-8', errors='replace')

    content = input_file.read()
    folded = v8log_to_folded(content)
    print(folded)

if __name__ == '__main__':
    main()
