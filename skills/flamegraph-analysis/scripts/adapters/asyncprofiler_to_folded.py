#!/usr/bin/env python3
# =============================================================================
# 脚本：asyncprofiler_to_folded.py
# 用途：将 async-profiler 输出转换为 folded 格式
# 使用：python3 asyncprofiler_to_folded.py [input_file]
# 参数：
#   input_file : async-profiler 输出文件（可选，默认从 stdin 读取）
# 说明：支持 async-profiler 的 HTML 格式和 collapsed 格式输出
# =============================================================================
import sys
import re

def asyncprofiler_html_to_folded(content: str) -> str:
    script_match = re.search(
        r'<script[^>]*>\s*var\s+data\s*=\s*\[(.*?)\];',
        content,
        re.DOTALL
    )
    if script_match:
        data_str = script_match.group(1)
        lines = re.findall(r'"([^"]*)"', data_str)
        folded_lines = []
        for line in lines:
            line = line.strip()
            if line and not line.startswith('#'):
                parts = line.rsplit(None, 1)
                if len(parts) == 2 and parts[1].isdigit():
                    folded_lines.append(line)
                elif len(parts) == 2 and re.match(r'[\d.]+$', parts[1]):
                    folded_lines.append(line)
        return '\n'.join(folded_lines)
    return ""

def asyncprofiler_collapsed_to_folded(content: str) -> str:
    folded_stacks = []

    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue

        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack_str, count_str = parts
            frames = stack_str.split(';')
            frames = [normalize_java_frame(f) for f in frames if f.strip()]
            if frames:
                try:
                    count = int(count_str)
                    folded_stacks.append(f"{';'.join(frames)} {count}")
                except ValueError:
                    pass

    return '\n'.join(folded_stacks)

def normalize_java_frame(frame: str) -> str:
    frame = re.sub(r'\(.*\)[VZIJBBCDFELS]?$', '', frame)
    frame = re.sub(r'\$\$Lambda\$\d+/0x[0-9a-f]+', '$$Lambda', frame)
    frame = re.sub(r'\$[0-9]+', '', frame)
    return frame

def main():
    if len(sys.argv) < 2:
        input_file = sys.stdin
    else:
        input_file = open(sys.argv[1], 'r', encoding='utf-8', errors='replace')

    content = input_file.read()

    if '<script' in content:
        folded = asyncprofiler_html_to_folded(content)
    else:
        folded = asyncprofiler_collapsed_to_folded(content)

    print(folded)

if __name__ == '__main__':
    main()
