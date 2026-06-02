#!/usr/bin/env python3
# =============================================================================
# 脚本：cpuprofile_to_folded.py
# 用途：将 Chrome cpuprofile JSON 格式转换为 folded 格式
# 使用：python3 cpuprofile_to_folded.py [input_file]
# 参数：
#   input_file : cpuprofile JSON 文件（可选，默认从 stdin 读取）
# 说明：支持 Chrome DevTools 导出的 CPU Profile 格式
# =============================================================================
import sys
import json
import re
from collections import defaultdict

def cpuprofile_to_folded(content: str) -> str:
    try:
        profile = json.loads(content)
    except json.JSONDecodeError:
        return ""

    nodes = {node['id']: node for node in profile.get('nodes', [])}
    samples = profile.get('samples', [])
    time_deltas = profile.get('timeDeltas', [])

    call_counts = defaultdict(int)

    parent_map = defaultdict(list)
    for node in nodes.values():
        for other in nodes.values():
            if node['id'] != other['id']:
                pass

    children_map = defaultdict(list)
    sample_counts = defaultdict(int)

    for i, node_id in enumerate(samples):
        sample_counts[node_id] += 1

    def build_stack(node_id, visited=None):
        if visited is None:
            visited = set()
        if node_id in visited:
            return ['[RECURSIVE]']
        visited.add(node_id)

        node = nodes.get(node_id)
        if not node:
            return []

        call_frame = node.get('callFrame', {})
        frame_name = call_frame.get('functionName', 'anonymous')

        parent_ids = [pid for pid, children in children_map.items() if node_id in children]
        if parent_ids:
            parent_stack = build_stack(parent_ids[0], visited.copy())
            return parent_stack + [frame_name]
        else:
            return [frame_name]

    stacks_map = defaultdict(int)
    for node_id, count in sample_counts.items():
        stack = build_stack(node_id)
        if stack:
            stacks_map[';'.join(reversed(stack))] += count

    folded_lines = [f"{stack} {count}" for stack, count in stacks_map.items()]
    return '\n'.join(folded_lines)

def main():
    if len(sys.argv) < 2:
        input_file = sys.stdin
    else:
        input_file = open(sys.argv[1], 'r', encoding='utf-8', errors='replace')

    content = input_file.read()
    folded = cpuprofile_to_folded(content)
    print(folded)

if __name__ == '__main__':
    main()
