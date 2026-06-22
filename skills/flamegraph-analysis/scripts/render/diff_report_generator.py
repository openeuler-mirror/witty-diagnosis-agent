#!/usr/bin/env python3
"""diff_report_generator.py — 差分火焰图报告生成器"""
import sys, os, json

BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(BASE, 'scripts'))
from analyzers.diff import parse_folded, diff_analysis
TEMPLATE_PATH = os.path.join(BASE, 'templates', 'flamegraph-diff-analysis.html')

def build_tree(bs, ts):
    tree = {'name': 'all', 'b': 0, 'c': 0, 'selfB': 0, 'selfC': 0, 'children': []}
    for stack in set(bs.keys()) | set(ts.keys()):
        node = tree
        frames = stack.split(';')
        for i, f in enumerate(frames):
            found = next((c for c in node.get('children', []) if c['name'] == f), None)
            if not found:
                found = {'name': f, 'b': 0, 'c': 0, 'selfB': 0, 'selfC': 0, 'children': []}
                node['children'].append(found)
            if i == len(frames) - 1:
                found['selfB'] += bs.get(stack, 0)
                found['selfC'] += ts.get(stack, 0)
            found['b'] += bs.get(stack, 0)
            found['c'] += ts.get(stack, 0)
            node = found
    return tree

def gen_summary(changes, base_total, tgt_total):
    net = tgt_total - base_total
    pct = (net / base_total * 100) if base_total > 0 else 0
    trend = f"当前版本相比基线增加了 {net} 采样（+{pct:.1f}%），整体性能有所回退。" if net > 0 else (
        f"当前版本相比基线减少了 {-net} 采样（{pct:.1f}%），整体性能有所改善。" if net < 0 else "当前版本与基线采样数基本一致。")
    regs = sorted([r for r in changes if r['diff'] > 0], key=lambda x: -x['diff'])[:5]
    imps = sorted([r for r in changes if r['diff'] < 0], key=lambda x: x['diff'])[:5]
    return trend, '; '.join([f"{r['stack'].split(';')[-1]}（+{r['diff']}，{r['pct_diff']:.1f}%）" for r in regs]) if regs else "无明显回退。", '; '.join([f"{r['stack'].split(';')[-1]}（{r['diff']}，{r['pct_diff']:.1f}%）" for r in imps]) if imps else "无明显改善。"

def generate_html(bf, tf, out):
    with open(bf) as f: bs, bt = parse_folded(f.read())
    with open(tf) as f: ts, tt = parse_folded(f.read())
    print(f'Baseline: {len(bs)} stacks, {bt} samples')
    print(f'Target:   {len(ts)} stacks, {tt} samples')
    dr = diff_analysis(bs, bt, ts, tt)
    print(f'Diff items: {len(dr["all_changes"])}')
    tree = build_tree(bs, ts)
    trend, reg, imp = gen_summary(dr['all_changes'], bt, tt)
    tops = sorted([c for c in dr['all_changes'] if c['diff'] > 0], key=lambda x: -x['diff'])[:3]
    rc = "主要回退点：" + "; ".join([f"{r['stack'].split(';')[-1]}（+{r['diff']}）" for r in tops]) if tops else "无明显回退。"
    with open(TEMPLATE_PATH, encoding="utf-8") as f:
        html = f.read()
    for k, v in {
        '{{BASELINE_VERSION}}': os.path.basename(bf).replace('.txt','').replace('.folded',''),
        '{{CURRENT_VERSION}}': os.path.basename(tf).replace('.txt','').replace('.folded',''),
        '{{EVENT_TYPE}}': 'CPU on-CPU', '{{SAMPLING_INFO}}': f'{bt} -> {tt}',
        '{{SERVICE_NAME}}': os.path.basename(bf),
        '{{LEGEND_TEXT}}': 'Delta', '{{PROFILE_TREE}}': json.dumps(tree, separators=(',',':')),
        '{{SUMMARY_TREND}}': trend, '{{SUMMARY_REGRESSION}}': reg,
        '{{SUMMARY_IMPROVEMENT}}': imp, '{{SUMMARY_ROOT_CAUSE}}': rc,
    }.items():
        html = html.replace(k, v)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'Output: {out} ({len(html)//1024}KB)')

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: python3 diff_report_generator.py <baseline_folded> <target_folded> [--output FILE]')
        sys.exit(1)
    o = 'diff_report.html'
    if '--output' in sys.argv: o = sys.argv[sys.argv.index('--output') + 1]
    generate_html(sys.argv[1], sys.argv[2], o)
