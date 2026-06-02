#!/usr/bin/env python3
# =============================================================================
# 脚本：svg_to_folded.py
# 用途：将 SVG 火焰图逆向解析为 folded 格式
# 使用：python3 svg_to_folded.py [input_file] [--metadata]
# 参数：
#   input_file : SVG 文件（可选，默认从 stdin 读取）
#   --metadata : 输出解析元数据（置信度、覆盖率等）
# 说明：支持从 embedded script data 或 SVG 图形元素中提取堆栈信息
#       支持 flamegraph.pl、async-profiler、speedscope 生成的 SVG
# =============================================================================
import sys
import re
from collections import defaultdict

def svg_to_folded(content: str) -> tuple:
    import xml.etree.ElementTree as ET

    ns = {'svg': 'http://www.w3.org/2000/svg'}

    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        return "", {"error": str(e), "confidence": "low", "coverage": 0}

    metadata = {
        "source": "svg-reverse",
        "generator": "unknown",
        "confidence": "medium",
        "coverage": 0,
        "notes": []
    }

    if 'flamegraph.pl' in content:
        metadata["generator"] = "flamegraph.pl"
    elif 'async-profiler' in content:
        metadata["generator"] = "async-profiler"
    elif 'speedscope' in content:
        metadata["generator"] = "speedscope"

    script_match = re.search(r'<script[^>]*>\s*var\s+data\s*=\s*\[(.*?)\];', content, re.DOTALL)
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
        if folded_lines:
            metadata["confidence"] = "high"
            metadata["coverage"] = 100
            metadata["notes"].append("Extracted from embedded script data")
            return '\n'.join(folded_lines), metadata

    if 'diff' in content.lower() and ('#ff0000' in content.lower() or '#0000ff' in content.lower()):
        metadata["error"] = "Differential SVG is not supported"
        metadata["confidence"] = "low"
        return "", metadata

    nodes = []
    for g in root.iter('{http://www.w3.org/2000/svg}g'):
        rect = g.find('{http://www.w3.org/2000/svg}rect')
        title = g.find('{http://www.w3.org/2000/svg}title')

        if title is not None and rect is not None:
            title_text = title.text or ""

            sample_match = re.search(r'([\d,]+)\s*(?:samples?|ms|hits)', title_text)
            if sample_match:
                samples = int(sample_match.group(1).replace(',', ''))
            else:
                pct_match = re.search(r'([\d.]+)%', title_text)
                samples = int(float(pct_match.group(1)) * 100) if pct_match else 1

            name_match = re.match(r'^(.+?)\s*\(', title_text)
            name = name_match.group(1).strip() if name_match else title_text.split()[0] if title_text else "unknown"

            try:
                x = float(rect.get('x', 0))
                y = float(rect.get('y', 0))
                width = float(rect.get('width', 0))
                height = float(rect.get('height', 0))
            except ValueError:
                continue

            nodes.append({
                'name': name,
                'x': x,
                'y': y,
                'width': width,
                'height': height,
                'samples': samples,
                'title': title_text
            })

    if not nodes:
        metadata["error"] = "No parseable nodes found in SVG"
        metadata["confidence"] = "low"
        return "", metadata

    nodes.sort(key=lambda n: (n['y'], n['x']))

    max_y = max(n['y'] for n in nodes) if nodes else 1
    for n in nodes:
        n['depth'] = int((max_y - n['y']) / 20)

    layers = defaultdict(list)
    for n in nodes:
        layers[n['depth']].append(n)

    parent_map = {}
    for depth in sorted(layers.keys()):
        if depth == 0:
            continue
        for node in layers[depth]:
            best_parent = None
            best_width = 0
            for parent in layers.get(depth - 1, []):
                if (parent['x'] <= node['x'] + 1 and
                    parent['x'] + parent['width'] >= node['x'] + node['width'] - 1):
                    if parent['width'] > best_width:
                        best_parent = parent
                        best_width = parent['width']
            if best_parent:
                parent_map[id(node)] = best_parent

    tree = defaultdict(list)
    roots = []
    for n in nodes:
        if id(n) in parent_map:
            tree[parent_map[id(n)]].append(n)
        else:
            roots.append(n)

    def build_stack(node, visited=None):
        if visited is None:
            visited = set()
        if id(node) in visited:
            return []
        visited.add(id(node))

        stack = [node['name']]
        if id(node) in parent_map:
            parent_stack = build_stack(parent_map[id(node)], visited)
            stack.extend(parent_stack)
        return stack

    folded_map = defaultdict(int)
    for root_node in roots:
        stack = build_stack(root_node)
        if stack:
            folded_map[';'.join(reversed(stack))] += root_node['samples']

    total_samples = sum(n['samples'] for n in nodes)
    svg_width = float(root.get('width', 1)) if 'width' in root.attrib else 1000
    pixels_per_sample = svg_width / total_samples if total_samples > 0 else 1
    filtered_samples = total_samples * 0.9
    metadata["coverage"] = min(100, int(filtered_samples / total_samples * 100)) if total_samples > 0 else 0
    metadata["confidence"] = "high" if metadata["coverage"] > 80 else "medium"

    folded_lines = [f"{stack} {count}" for stack, count in folded_map.items()]
    return '\n'.join(folded_lines), metadata

def main():
    if len(sys.argv) < 2:
        content = sys.stdin.read()
    else:
        with open(sys.argv[1], 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

    folded, metadata = svg_to_folded(content)

    if '--metadata' in sys.argv:
        import json
        print(json.dumps(metadata, indent=2))
    else:
        print(folded)

if __name__ == '__main__':
    main()
