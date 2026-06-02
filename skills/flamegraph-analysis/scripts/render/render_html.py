#!/usr/bin/env python3
# =============================================================================
# 脚本：render_html.py
# 用途：基于模板生成带数据的完整 HTML 火焰图报告
# 使用：python3 render_html.py --input PROFILE_JSON --findings FINDINGS_JSON [--output FILE]
# 参数：
#   --input FILE      : profile-data JSON 文件
#   --findings FILE   : findings JSON 文件
#   --title STR       : 报告标题（默认: Flame Graph Report）
#   --filename STR    : 文件名元数据
#   --format STR      : 格式元数据（默认: folded）
#   --event STR       : 事件类型（默认: cpu-cycles）
#   --duration STR    : 采样时长
#   --confidence STR  : 置信度（high/medium/low）
#   --output FILE     : 输出 HTML 文件
#   --output-dir DIR  : 输出目录
#   --help / -h       : 显示帮助信息
# 说明：基于 flamegraph-viewer.html 模板生成交互式火焰图报告
# =============================================================================

import json
import argparse
import os
import sys
import re
from datetime import datetime, timezone

# 添加当前模块路径
if __name__ == '__main__':
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

# 模板路径
TEMPLATE_PATH = os.path.join(os.path.dirname(__file__), '..', '..', 'templates', 'flamegraph-viewer.html')


def main():
    parser = argparse.ArgumentParser(description='Render HTML flamegraph')
    parser.add_argument('--input', '-i', help='Input profile-data JSON file', required=True)
    parser.add_argument('--findings', '-f', help='Findings JSON file', required=True)
    parser.add_argument('--title', '-t', help='Report title', default='Flame Graph Report')
    parser.add_argument('--filename', help='Filename metadata', default='unknown')
    parser.add_argument('--format', help='Format metadata', default='folded')
    parser.add_argument('--event', help='Event metadata (e.g., cpu-cycles)', default='cpu-cycles')
    parser.add_argument('--duration', help='Duration metadata', default='')
    parser.add_argument('--confidence', help='Confidence (high/medium/low)', default='high')
    parser.add_argument('--output', '-o', help='Output HTML file (ignored if --output-dir is set)')
    parser.add_argument('--output-dir', '-d', help='Output directory for all files')

    args = parser.parse_args()

    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        if args.output:
            args.output = os.path.join(args.output_dir, os.path.basename(args.output))
        else:
            args.output = os.path.join(args.output_dir, 'flamegraph.html')

    # 读取模板
    with open(TEMPLATE_PATH, 'r', encoding='utf-8') as f:
        html = f.read()

    # 读取 profile-data
    with open(args.input, 'r', encoding='utf-8') as f:
        profile_data_json = json.dumps(json.load(f), separators=(',', ':'))

    # 读取 findings
    findings_for_html = []
    causal_analysis = {}
    summary_stats = {
        'findings': 0,
        'top_hotspot_pct': 0,
        'frames': 0,
        'max_depth': 0
    }
    summary_body = ''
    sample_count = 0

    if os.path.exists(args.findings):
        try:
            with open(args.findings, 'r', encoding='utf-8') as f:
                data = json.load(f)
                findings_for_html = data.get('findings', [])
                causal_analysis = data.get('causal_analysis', {})
                summary_stats['findings'] = len(findings_for_html)

                # 计算 top hotspot
                if findings_for_html:
                    top = max(findings_for_html, key=lambda x: x.get('metrics', {}).get('percent', 0))
                    summary_stats['top_hotspot_pct'] = top.get('metrics', {}).get('percent', 0)

                # 构建 summary body
                # 优先使用 AI 生成的 causal_analysis.summary，否则 fallback 到字符串拼接
                if causal_analysis.get('summary'):
                    summary_body = causal_analysis['summary']
                elif findings_for_html:
                    top_findings = sorted(findings_for_html,
                                          key=lambda x: x.get('metrics', {}).get('percent', 0), reverse=True)[:2]
                    
                    summary_parts = []
                    for i, f in enumerate(top_findings):
                        pct = f.get('metrics', {}).get('percent', 0)
                        title = f['title']
                        leaf = f.get('evidence_leaf', '...')

                        if i == 0:
                            summary_parts.append(
                                f'{title} 是主要瓶颈 — '
                                f'CPU 时间的 <strong>{pct}%</strong> 消耗在 '
                                f'<code style="font-family:ui-monospace,monospace;font-size:12px;background:var(--bg-subtle);padding:1px 4px;border-radius:3px">{leaf}</code>。'
                            )
                        else:
                            summary_parts.append(
                                f' {title} 是次要开销，贡献了 <strong>{pct}%</strong>，来自 {leaf}。'
                            )
                    
                    if len(top_findings) == 1:
                        summary_body = summary_parts[0]
                    else:
                        summary_body = ' '.join(summary_parts)
        except Exception as e:
            print(f'Warning: Could not read findings: {e}')

    # 从 profile-data 计算统计
    try:
        with open(args.input, 'r', encoding='utf-8') as f:
            profile_data = json.load(f)
            sample_count = profile_data.get('value', 0)

            # 计算 max depth 和 frames
            def count_frames_and_depth(node, depth=0, max_depth=0):
                new_max = max(max_depth, depth)
                total_frames = 1
                if 'children' in node:
                    for child in node['children']:
                        child_frames, child_depth = count_frames_and_depth(child, depth + 1, new_max)
                        total_frames += child_frames
                        new_max = max(new_max, child_depth)
                return total_frames, new_max

            frames, max_depth = count_frames_and_depth(profile_data)
            summary_stats['frames'] = frames
            summary_stats['max_depth'] = max_depth
    except Exception as e:
        print(f'Warning: Could not compute stats from profile-data: {e}')

    findings_json = json.dumps(findings_for_html, separators=(',', ':'))

    # 替换 meta 数据
    replacements = {
        'order-service-2024-05-03.perf': args.filename,
        'perf script': args.format,
        'cpu-cycles': args.event,
        '100,000': f'{sample_count:,}',
        '30s': args.duration,
        '● 高置信度': f'● {args.confidence} 置信度'
    }

    for old, new in replacements.items():
        if new:
            html = html.replace(old, new)

    # 替换 summary
    def replace_summary_section(html_content):
        """替换 summary 卡片部分"""
        # 替换 summary-body 内容
        if summary_body:
            # 将 Markdown 转换为 HTML
            body_html = summary_body
            # 转换 `` `code` `` 为 <code>code</code>
            body_html = re.sub(r'`([^`]+)`', r'<code style="font-family:ui-monospace,monospace;font-size:12px;background:var(--bg-subtle);padding:1px 4px;border-radius:3px">\1</code>', body_html)
            # 转换 **bold** 为 <strong>bold</strong>
            body_html = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', body_html)
            # 转换 *italic* 为 <em>italic</em>
            body_html = re.sub(r'(?<!\*)\*([^*]+)\*(?!\*)', r'<em>\1</em>', body_html)
            
            # 找到 <p class="summary-body"> 并替换其内容
            pattern = r'(<p class="summary-body">)(.*?)(</p>)'
            replacement = rf'\g<1>{body_html}\3'
            html_content = re.sub(pattern, replacement, html_content, flags=re.DOTALL)
        
        # 直接替换统计数字（不依赖位置）
        html_content = html_content.replace('>4<', f'>{summary_stats["findings"]}<', 1)
        html_content = html_content.replace('>17.5<', f'>{summary_stats["top_hotspot_pct"]}<', 1)
        html_content = html_content.replace('>75<', f'>{summary_stats["frames"]}<', 1)
        html_content = html_content.replace('>11<', f'>{summary_stats["max_depth"]}<', 1)
        
        return html_content

    html = replace_summary_section(html)

    # 替换数据
    # 找到 profile-data script
    profile_start = html.find('<script id="profile-data"')
    profile_end = html.find('</script>', profile_start)
    before_profile = html[:profile_start]
    after_profile = html[profile_end + len('</script>'):]

    # 找到 findings-data script
    findings_start = after_profile.find('<script id="findings-data"')
    findings_end = after_profile.find('</script>', findings_start)
    before_findings = after_profile[:findings_start]
    after_findings = after_profile[findings_end + len('</script>'):]

    # 构建新 HTML
    html = (
        before_profile
        + f'<script id="profile-data" type="application/json">{profile_data_json}</script>'
        + before_findings
        + f'<script id="findings-data" type="application/json">{findings_json}</script>'
        + after_findings
    )

    # 更新生成时间
    now_str = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    html = html.replace('2024-05-03 14:32 UTC', now_str)

    # 输出
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(html)

    print(f'Generated HTML in {args.output}')


if __name__ == '__main__':
    main()