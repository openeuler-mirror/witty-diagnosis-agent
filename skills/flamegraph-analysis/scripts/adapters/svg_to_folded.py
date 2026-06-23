#!/usr/bin/env python3
# =============================================================================
# 脚本：svg_to_folded.py (fixed)
# 用途：将 SVG 火焰图逆向解析为 folded 格式
# 使用：python3 svg_to_folded.py [input_file] [--metadata]
# 参数：
#   input_file : SVG 文件（可选，默认从 stdin 读取）
#   --metadata : 输出解析元数据（置信度、覆盖率等）
# 说明：支持从 embedded script data 或 SVG 图形元素中提取堆栈信息
#       支持 flamegraph.pl、async-profiler、speedscope 生成的 SVG
# 修复：
#   v2 - 深度计算改为按 Y 坐标聚类，父节点选择改用重叠比例，
#        只输出叶节点堆栈，确定性排序，置信度基于像素覆盖率
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

    # --- Attempt 1: Extract from embedded script data ---
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

    # --- Skip differential SVG ---
    if 'diff' in content.lower() and ('#ff0000' in content.lower() or '#0000ff' in content.lower()):
        metadata["error"] = "Differential SVG is not supported"
        metadata["confidence"] = "low"
        return "", metadata

    # --- Attempt 2: Parse from SVG <g><rect><title> elements ---
    nodes = []
    ns_svg = '{http://www.w3.org/2000/svg}'

    for g in root.iter(ns_svg + 'g'):
        rect = g.find(ns_svg + 'rect')
        if rect is None:
            continue

        title_el = g.find(ns_svg + 'title')
        text_el = g.find(ns_svg + 'text')
        # Prefer title, fall back to text
        label_el = title_el
        if label_el is None:
            label_el = text_el

        if label_el is None:
            continue

        title_text = label_el.text or ""
        if not title_text.strip():
            if len(label_el) > 0 and label_el[0].text:
                title_text = label_el[0].text

        # Extract sample count
        samples = 1
        sample_match = re.search(r'([\d,]+)\s*(?:samples?|ms|hits)', title_text)
        if sample_match:
            samples = int(sample_match.group(1).replace(',', ''))
        else:
            num_match = re.search(r'(\d+)\s*$', title_text)
            if num_match:
                samples = int(num_match.group(1))
            else:
                pct_match = re.search(r'([\d.]+)%', title_text)
                if pct_match:
                    samples = int(float(pct_match.group(1)) * 100)

        # Extract function name
        name = "unknown"
        name_match = re.match(r'^(.+?)\s*\((?:[\d,.]+)\s*(?:samples?|ms|hits|%)', title_text)
        if name_match:
            name = name_match.group(1).strip()
        else:
            parts = title_text.rsplit(None, 1)
            if len(parts) == 2 and parts[1].replace(',', '').replace('.', '').isdigit():
                name = parts[0].strip()
            else:
                name = title_text.split()[0] if title_text else "unknown"

        try:
            x = float(rect.get('x', 0))
            y = float(rect.get('y', 0))
            width = float(rect.get('width', 0))
            height = float(rect.get('height', 0))
        except ValueError:
            continue

        if width <= 0 or height <= 0:
            continue

        nodes.append({
            'name': name, 'x': x, 'y': y,
            'width': width, 'height': height,
            'samples': samples, 'title': title_text
        })
    if not nodes:
        # Try flat rect structure (old SVG format: rects without g wrappers)
        flat_nodes = []
        svg_root = root
        prev_text = ""
        for elem in svg_root:
            tag = elem.tag
            if tag == ns_svg + 'text':
                prev_text = elem.text or ""
            elif tag == ns_svg + 'rect':
                rx = elem.get('rx')
                ry = elem.get('ry')
                if rx and ry:  # Frame rects have rx="2" ry="2"
                    try:
                        x = float(elem.get('x', 0))
                        y = float(elem.get('y', 0))
                        width = float(elem.get('width', 0))
                        height = float(elem.get('height', 0))
                    except ValueError:
                        continue
                    if width <= 0 or height <= 0:
                        continue
                    # Extract name from preceding text or class
                    name = prev_text.strip() if prev_text.strip() else "unknown"
                    # Estimate sample count from width (proportional)
                    samples = max(1, int(width * 100 / 1200))
                    flat_nodes.append({
                        'name': name, 'x': x, 'y': y,
                        'width': width, 'height': height,
                        'samples': samples, 'title': name
                    })
        
        if flat_nodes:
            nodes = flat_nodes
            metadata["notes"].append("Parsed from flat rect structure (old format)")
    
    if not nodes:
        metadata["error"] = "No parseable nodes found in SVG"
        metadata["confidence"] = "low"
        return "", metadata

    # --- Depth assignment by unique Y positions (not hardcoded 20px) ---
    # Cluster Y values within 0.5px tolerance
    eps = 0.5
    ys = sorted(set(round(n['y'], 1) for n in nodes))
    # Further cluster close Ys
    clustered_ys = []
    for y in ys:
        if clustered_ys and abs(y - clustered_ys[-1]) < eps:
            continue
        clustered_ys.append(y)
    y_to_depth = {y: i for i, y in enumerate(clustered_ys)}
    # Assign depth: map each node's Y to nearest clustered Y
    for n in nodes:
        closest_y = min(clustered_ys, key=lambda cy: abs(n['y'] - cy))
        n['depth'] = y_to_depth[closest_y]

    # --- Layer grouping ---
    layers = defaultdict(list)
    for n in nodes:
        layers[n['depth']].append(n)

    # --- Tree reconstruction: parent selection by horizontal overlap ---
    parent_map = {}
    for depth in sorted(layers.keys()):
        if depth == 0:
            continue
        for node in layers[depth]:
            node_left = node['x']
            node_right = node['x'] + node['width']
            node_center = node['x'] + node['width'] / 2

            best_parent = None
            best_parent_width = float('inf')

            for parent in layers.get(depth - 1, []):
                parent_left = parent['x']
                parent_right = parent['x'] + parent['width']

                # Check containment: parent must cover the node horizontally
                # Use overlap fraction
                overlap = max(0.0, min(node_right, parent_right) - max(node_left, parent_left))
                overlap_ratio = overlap / node['width'] if node['width'] > 0 else 0

                if overlap_ratio >= 0.5:
                    # Pick the most specific (smallest width) parent
                    if parent['width'] < best_parent_width:
                        best_parent = parent
                        best_parent_width = parent['width']

            if best_parent:
                parent_map[id(node)] = best_parent

    # --- Build children map ---
    children_map = defaultdict(list)
    for node in nodes:
        if id(node) in parent_map:
            parent = parent_map[id(node)]
            children_map[id(parent)].append(node)

    # --- Stack reconstruction (leaf nodes only) ---
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
    for n in nodes:
        # Only emit stacks for leaf nodes (no children in reconstructed tree)
        # OR if the original format included all nodes, fallback to all
        if len(children_map.get(id(n), [])) > 0:
            # Internal node - skip (its samples are accounted for in leaves)
            # UNLESS this is the root frame (depth 0)
            if n['depth'] > 0:
                continue
        stack = build_stack(n)
        if stack:
            # Reverse so root is first: root;child;...;leaf
            folded_map[';'.join(reversed(stack))] += n['samples']

    # If no leaf stacks found (shouldn't happen), fallback: emit all nodes
    if not folded_map:
        for n in nodes:
            stack = build_stack(n)
            if stack:
                folded_map[';'.join(reversed(stack))] += n['samples']

    # --- Coverage and confidence ---
    total_samples = sum(n['samples'] for n in nodes)
    svg_width = float(root.get('width', 1)) if 'width' in root.attrib else 1000

    # Pixel coverage: fraction of SVG width spanned by parsed frame-widths
    if svg_width > 0:
        pixel_coverage = min(100, sum(n['width'] for n in nodes) / svg_width * 100)
    else:
        pixel_coverage = 0

    metadata["coverage"] = min(100, int(pixel_coverage))
    if len(nodes) > 10 and pixel_coverage > 50:
        metadata["confidence"] = "high"
    elif len(nodes) > 0:
        metadata["confidence"] = "medium"
    else:
        metadata["confidence"] = "low"

    # --- Deterministic output sorting ---
    folded_lines = []
    for stack, count in sorted(folded_map.items(), key=lambda x: (-x[1], x[0])):
        folded_lines.append(f"{stack} {count}")

    return '\n'.join(folded_lines), metadata


def main():
    if len(sys.argv) < 2 or sys.argv[1] == '-':
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
