#!/usr/bin/env python3
# =============================================================================
# 脚本：folded_utils.py
# 用途：折叠格式工具函数库（解析、规范化、合并、转换等）
# 使用：python3 folded_utils.py <command> [args]
# 命令：
#   parse <file>          - 解析 folded 文件
#   normalize <file>      - 规范化 folded 内容
#   hierarchy <file>      - 转换为层级 JSON
#   summarize <file>      - 汇总 folded 文件
#   metadata <file>       - 提取元数据
# =============================================================================
import sys
import re
import json
from typing import Dict, List, Tuple

JAVA_PACKAGE_PREFIXES = (
    'java/', 'javax/', 'jdk/', 'net/', 'org/', 'com/', 'io/', 'sun/',
    'Lorg/', 'Lcom/', 'Lio/', 'Lnet/', 'Ljavax/', 'Ljdk/', 'Lsun/',
)


def is_java_frame(func: str) -> bool:
    return func.startswith(JAVA_PACKAGE_PREFIXES) or '/gen/' in func


def tidy_generic(func: str) -> str:
    if ';' in func:
        func = func.replace(';', ':')
    if not re.search(r'\.\(.*\)\.', func):
        func = re.sub(r'\(.*', '', func)
    func = re.sub(r'"|\'', '', func)
    func = func.strip()
    return func


def tidy_java(func: str) -> str:
    if func.startswith('L') and '/' in func:
        func = func[1:]
    return func


def tidy_cpp(func: str) -> str:
    func = re.sub(r'(::.*)[(<].*', r'\1', func)
    return func


def normalize_frame(func: str, pname: str = '', annotate_kernel: bool = False,
                    annotate_jit: bool = False, module: str = '',
                    include_addrs: bool = False, pc: str = '',
                    is_inline: bool = False) -> str:
    func = tidy_generic(func)

    if pname == 'java' or is_java_frame(func):
        func = tidy_java(func)
    else:
        func = tidy_cpp(func)

    if is_inline and not func.endswith('_i]'):
        func += '_[i]'
    elif annotate_kernel and module and re.search(r'(\[|vmlinux$)', module) and 'unknown' not in module:
        if not func.endswith('_k]'):
            func += '_[k]'
    elif annotate_jit and module and re.search(r'/tmp/perf-\d+\.map', module):
        if not func.endswith('_j]'):
            func += '_[j]'

    if include_addrs and pc:
        func = f'[{func} <{pc}>]'

    return func


def parse_folded(content: str) -> List[Tuple[str, int]]:
    stacks = []
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            try:
                count = int(count)
                stacks.append((stack, count))
            except ValueError:
                stacks.append((line, 1))
        else:
            stacks.append((line, 1))
    return stacks


def normalize_folded(content: str) -> str:
    lines = []
    for line in content.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            lines.append(line)
            continue
        parts = line.rsplit(None, 1)
        if len(parts) == 2:
            stack, count = parts
            frames = stack.split(';')
            frames = [f.strip() for f in frames if f.strip()]
            if frames:
                lines.append(';'.join(frames) + ' ' + count)
    return '\n'.join(lines)


def extract_metadata(content: str) -> Dict[str, str]:
    metadata = {}
    for line in content.split('\n')[:50]:
        line = line.strip()
        if not line.startswith('#'):
            break
        if ':' in line:
            key, value = line[1:].split(':', 1)
            metadata[key.strip()] = value.strip()
    return metadata


def merge_stacks(stacks1: List[Tuple[str, int]], stacks2: List[Tuple[str, int]]) -> List[Tuple[str, int]]:
    merged = {}
    for stack, count in stacks1:
        merged[stack] = merged.get(stack, 0) + count
    for stack, count in stacks2:
        merged[stack] = merged.get(stack, 0) + count
    return [(stack, count) for stack, count in merged.items()]


def filter_stacks(stacks: List[Tuple[str, int]], min_count: int = 1) -> List[Tuple[str, int]]:
    return [(stack, count) for stack, count in stacks if count >= min_count]


def sort_stacks(stacks: List[Tuple[str, int]], by_count: bool = True) -> List[Tuple[str, int]]:
    if by_count:
        return sorted(stacks, key=lambda x: -x[1])
    return sorted(stacks, key=lambda x: x[0])


def stacks_to_folded(stacks: List[Tuple[str, int]]) -> str:
    lines = [f"{stack} {count}" for stack, count in stacks]
    return '\n'.join(lines)


def folded_to_hierarchy(content: str) -> dict:
    stacks = parse_folded(content)
    root = {'name': 'all', 'children': {}}

    for stack, count in stacks:
        frames = stack.split(';')
        current = root
        for i, frame in enumerate(frames):
            if frame not in current['children']:
                current['children'][frame] = {
                    'name': frame,
                    'children': {},
                    'value': 0
                }
            current['children'][frame]['value'] += count
            current = current['children'][frame]

    def children_to_list(node):
        if not node['children']:
            return {'name': node['name'], 'value': node['value']}
        return {
            'name': node['name'],
            'value': node['value'],
            'children': [children_to_list(c) for c in node['children'].values()]
        }

    return {
        'name': 'all',
        'value': sum(c for _, c in stacks),
        'children': [children_to_list(c) for c in root['children'].values()]
    }


def summarize_stacks(content: str, top_n: int = 10) -> Dict:
    stacks = parse_folded(content)
    total = sum(count for _, count in stacks)

    sorted_stacks = sorted(stacks, key=lambda x: -x[1])
    top_stacks = sorted_stacks[:top_n]

    frame_counts = {}
    for stack, count in stacks:
        for frame in stack.split(';'):
            frame_counts[frame] = frame_counts.get(frame, 0) + count

    top_frames = sorted(frame_counts.items(), key=lambda x: -x[1])[:top_n]

    return {
        'total_samples': total,
        'unique_stacks': len(stacks),
        'top_stacks': [
            {'stack': stack, 'count': count, 'percent': count / total * 100}
            for stack, count in top_stacks
        ],
        'top_frames': [
            {'frame': frame, 'count': count, 'percent': count / total * 100}
            for frame, count in top_frames
        ]
    }


def main():
    if len(sys.argv) < 2:
        print('Usage: folded_utils.py <command> [args]')
        print('Commands:')
        print('  parse <file>          - Parse folded file')
        print('  normalize <file>      - Normalize folded content')
        print('  hierarchy <file>      - Convert to hierarchy JSON')
        print('  summarize <file>      - Summarize folded file')
        print('  metadata <file>       - Extract metadata')
        sys.exit(1)

    command = sys.argv[1]
    file_path = sys.argv[2] if len(sys.argv) > 2 else None

    if file_path:
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    else:
        content = sys.stdin.read()

    if command == 'parse':
        stacks = parse_folded(content)
        for stack, count in stacks[:20]:
            print(f"{stack} {count}")
    elif command == 'normalize':
        print(normalize_folded(content))
    elif command == 'hierarchy':
        hierarchy = folded_to_hierarchy(content)
        print(json.dumps(hierarchy, indent=2))
    elif command == 'summarize':
        summary = summarize_stacks(content)
        print(json.dumps(summary, indent=2))
    elif command == 'metadata':
        metadata = extract_metadata(content)
        print(json.dumps(metadata, indent=2))
    else:
        print(f'Unknown command: {command}')
        sys.exit(1)


if __name__ == '__main__':
    main()
