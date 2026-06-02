#!/usr/bin/env python3
# =============================================================================
# 脚本：folded_to_hierarchy.py
# 用途：将折叠栈格式转换为 flamegraph-viewer.html 所需的 profile-data 格式
# 使用：python3 folded_to_hierarchy.py --input FOLDED_FILE [--findings FILE] [--output FILE]
# 参数：
#   --input FILE      : 输入 folded 文件
#   --findings FILE   : Findings JSON 文件（用于标记节点）
#   --output FILE     : 输出 JSON 文件
#   --output-dir DIR  : 输出目录
#   --help / -h       : 显示帮助信息
# 功能：
#   - 自动分类（lock、gc、io、syscall、crypto、reflection 等）
#   - 自动识别模块（user-code、library、runtime、kernel、native）
#   - 提取注解标记（_k]、_j]、_i] 等）
#   - 支持 findings 路径标记
# =============================================================================

import json
import argparse
import os
import sys
import re
from typing import Dict, List, Any, Tuple
from collections import defaultdict

# 添加当前模块路径
if __name__ == '__main__':
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# 类别匹配关键词（用于自动分类）
CATEGORY_KEYWORDS = {
    'lock': ['lock', 'mutex', 'futex', 'park', 'wait', 'sync', 'monitor', 'synchronized', 'ReentrantLock'],
    'gc': ['gc', 'garbage', 'collect', 'mark', 'evac', 'alloc', 'new', 'Heap', 'Eden', 'Survivor', 'Tenured'],
    'io': ['read', 'write', 'socket', 'recv', 'send', 'io', 'file', 'fread', 'fwrite', 'InputStream', 'OutputStream'],
    'syscall': ['syscall', 'sys_', 'kernel', '__kernel_', 'sys_enter', 'sys_exit'],
    'crypto': ['encrypt', 'decrypt', 'sign', 'verify', 'rsa', 'aes', 'sha', 'hash', 'ssl', 'tls', 'Cipher', 'MessageDigest'],
    'reflection': ['reflect', 'invoke', 'method', 'field', 'proxy', 'accessor', 'Reflection'],
    'network': ['connect', 'accept', 'bind', 'listen', 'http', 'tcp', 'udp', 'netty', 'OkHttp'],
    'thread': ['Thread', 'Runnable', 'Executor', 'ForkJoin', 'pool', 'worker'],
    'database': ['jdbc', 'mysql', 'postgresql', 'redis', 'mongodb', 'sql', 'Statement', 'PreparedStatement'],
    'compression': ['compress', 'decompress', 'gzip', 'zip', 'lz4', 'snappy'],
    'logging': ['log', 'Logger', 'Log4j', 'SLF4J', 'JUL'],
    'exception': ['Exception', 'Throwable', 'Error', 'throw', 'catch'],
    'classloader': ['ClassLoader', 'defineClass', 'loadClass'],
    'jni': ['JNI', 'JavaNI', 'native', '_JNI', 'CallStatic'],
}

CATEGORY_DEFAULT = 'compute'

MODULE_KEYWORDS = {
    'user-code': ['main', 'app', 'application', 'controller', 'service', 'handler', 'com.', 'org.', 'net.'],
    'library': ['lib', 'library', 'framework', 'apache.', 'spring.', 'com.google.', 'io.netty.'],
    'runtime': ['runtime', 'jvm', 'go', 'python', 'node', 'java.lang.', 'java.util.', 'jdk.internal.'],
    'kernel': ['kernel', 'sys_', 'vmlinux', '[k]', '_k]'],
    'native': ['libc', 'libm', 'libpthread', 'ld-linux', 'libjvm'],
}

MODULE_DEFAULT = 'unknown'

# 注解标记模式（从 FlameGraph 的 stackcollapse 脚本参考）
ANNOTATION_PATTERNS = {
    'kernel': re.compile(r'_k\]$|\[k\]|\(kernel\)'),
    'jit': re.compile(r'_j\]$|\[j\]|\(jit\)'),
    'inline': re.compile(r'_i\]$|\[i\]|\(inline\)'),
    'user': re.compile(r'_u\]$|\[u\]|\(user\)'),
}

def extract_annotations(frame: str) -> Dict[str, bool]:
    """从帧名称中提取注解标记"""
    annotations = {}
    for annot_type, pattern in ANNOTATION_PATTERNS.items():
        annotations[annot_type] = bool(pattern.search(frame))
    return annotations


def parse_folded(file_path: str) -> List[Tuple[str, int]]:
    """解析 folded 文件"""
    stacks = []
    with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.rsplit(' ', 1)
            if len(parts) == 2:
                stack = parts[0]
                try:
                    count = int(parts[1])
                    stacks.append((stack, count))
                except ValueError:
                    stacks.append((line, 1))
            else:
                stacks.append((line, 1))
    return stacks


def guess_category(frame: str) -> str:
    """根据函数名猜测类别"""
    frame_lower = frame.lower()
    for cat, keywords in CATEGORY_KEYWORDS.items():
        if any(kw in frame_lower for kw in keywords):
            return cat
    return CATEGORY_DEFAULT


def guess_module(frame: str) -> str:
    """根据函数名猜测模块"""
    frame_lower = frame.lower()
    for mod, keywords in MODULE_KEYWORDS.items():
        if any(kw in frame_lower for kw in keywords):
            return mod
    return MODULE_DEFAULT


def build_hierarchy(stacks: List[Tuple[str, int]], findings: List[Dict] = None) -> Dict[str, Any]:
    """构建层级结构，支持注解标记和元数据提取"""
    # 构建 finding 路径映射（用于标记哪些节点属于 finding）
    finding_path_map = {}
    if findings:
        for f in findings:
            ep = f.get('evidence_path', [])
            for i in range(1, len(ep) + 1):
                path_tuple = tuple(ep[:i])
                if path_tuple not in finding_path_map:
                    finding_path_map[path_tuple] = []
                finding_path_map[path_tuple].append(f['id'])

    root = {
        'name': 'all',
        'value': 0,
        'self_value': 0,
        'module': 'root',
        'category': None,
        'finding_ids': [],
        'children': [],
        'annotations': {},
        'metadata': {
            'total_samples': 0,
            'unique_stacks': len(stacks),
            'category_distribution': defaultdict(int),
            'module_distribution': defaultdict(int),
        }
    }

    for stack_str, count in stacks:
        frames = stack_str.split(';')
        if not frames:
            continue

        # 更新 root 总计数
        root['value'] += count
        root['metadata']['total_samples'] += count

        current = root
        current_path = ['all']

        # 逐个处理栈帧（从根到叶）
        for i, frame in enumerate(frames):
            if not frame:
                continue

            # 查找或创建子节点
            child = next((c for c in current['children'] if c['name'] == frame), None)
            if child is None:
                # 新节点，初始化
                category = guess_category(frame)
                module = guess_module(frame)
                annotations = extract_annotations(frame)
                current_path.append(frame)

                # 查找是否属于 finding
                finding_ids = finding_path_map.get(tuple(current_path), [])

                # 更新分类和模块分布
                root['metadata']['category_distribution'][category] += count
                root['metadata']['module_distribution'][module] += count

                child = {
                    'name': frame,
                    'value': 0,
                    'self_value': 0,
                    'module': module,
                    'category': category,
                    'finding_ids': finding_ids,
                    'children': [],
                    'annotations': annotations,
                    'is_kernel': annotations.get('kernel', False),
                    'is_jit': annotations.get('jit', False),
                    'is_inline': annotations.get('inline', False),
                }
                current['children'].append(child)

            # 更新值
            child['value'] += count

            # 移动到子节点
            current = child
            current_path.append(frame)

        # 最后一个节点，更新 self_value
        if current['name'] != 'all':
            current['self_value'] += count

    # 按 value 降序排序子节点
    def sort_children(node: Dict):
        node['children'].sort(key=lambda x: -x['value'])
        for child in node['children']:
            sort_children(child)

    sort_children(root)

    # 将分布转换为列表格式以便于 JSON 序列化
    root['metadata']['category_distribution'] = [
        {'name': cat, 'value': cnt}
        for cat, cnt in sorted(root['metadata']['category_distribution'].items(), key=lambda x: -x[1])
    ]
    root['metadata']['module_distribution'] = [
        {'name': mod, 'value': cnt}
        for mod, cnt in sorted(root['metadata']['module_distribution'].items(), key=lambda x: -x[1])
    ]

    return root


def main():
    parser = argparse.ArgumentParser(description='Convert folded format to flamegraph hierarchy JSON')
    parser.add_argument('--input', '-i', help='Input folded file', required=True)
    parser.add_argument('--findings', '-f', help='Findings JSON file (for marking nodes)')
    parser.add_argument('--output', '-o', help='Output JSON file (ignored if --output-dir is set)')
    parser.add_argument('--output-dir', '-d', help='Output directory for all files')

    args = parser.parse_args()

    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        if args.output:
            args.output = os.path.join(args.output_dir, os.path.basename(args.output))
        else:
            args.output = os.path.join(args.output_dir, 'profile-data.json')

    # 读取 folded
    stacks = parse_folded(args.input)

    # 读取 findings
    findings = []
    if args.findings and os.path.exists(args.findings):
        try:
            with open(args.findings, 'r', encoding='utf-8') as f:
                data = json.load(f)
                findings = data.get('findings_for_html', data.get('findings', []))
        except Exception as e:
            print(f'Warning: Could not read findings: {e}')

    # 构建层级
    root = build_hierarchy(stacks, findings)

    # 输出
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(root, f, separators=(',', ':'))

    print(f'Generated hierarchy in {args.output}')


if __name__ == '__main__':
    main()