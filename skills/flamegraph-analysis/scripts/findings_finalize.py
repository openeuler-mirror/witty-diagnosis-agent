#!/usr/bin/env python3
# =============================================================================
# 脚本：findings_finalize.py
# 用途：对 findings.json 进行最终处理
#       1. 推断 findings 之间的结构化关系（parent_of / causes）
#       2. 生成修复优先级
#       3. 将大模型生成的根因总结注入 causal_analysis.summary
#       供 HTML 火焰图和 Markdown 报告共用
# 用法：python findings_finalize.py --input findings.json --summary "根因总结文本" [--output findings.json]
# =============================================================================

import json
import sys
from typing import Dict, List, Any


def load_findings(path: str) -> Dict[str, Any]:
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def infer_relations(findings: List[Dict[str, Any]]) -> List[Dict[str, str]]:
    relations = []
    for i, f_a in enumerate(findings):
        for j, f_b in enumerate(findings):
            if i >= j:
                continue
            path_a = f_a.get('evidence_path', [])
            path_b = f_b.get('evidence_path', [])

            if len(path_a) < len(path_b) and path_a == path_b[:len(path_a)]:
                relations.append({
                    'from': f_a['id'],
                    'to': f_b['id'],
                    'type': 'parent_of',
                    'description': f"{f_a['id']} 是 {f_b['id']} 的上游调用者"
                })

            title_a = f_a.get('title', '').lower()
            title_b = f_b.get('title', '').lower()
            if ('gc' in title_a or '垃圾' in title_a) and ('allocate' in title_b or '分配' in title_b or 'serialize' in title_b.lower() or '序列化' in title_b):
                relations.append({
                    'from': f_b['id'],
                    'to': f_a['id'],
                    'type': 'causes',
                    'description': f"{f_b['id']} 的高频分配导致 {f_a['id']} GC 压力"
                })

            if ('lock' in title_a or '锁' in title_a) and ('io' in title_b or 'write' in title_b or 'read' in title_b or 'send' in title_b):
                relations.append({
                    'from': f_b['id'],
                    'to': f_a['id'],
                    'type': 'causes',
                    'description': f"{f_b['id']} 的 I/O 延迟导致 {f_a['id']} 锁持有时间变长"
                })

    seen = set()
    unique_relations = []
    for r in relations:
        key = (r['from'], r['to'], r['type'])
        if key not in seen:
            seen.add(key)
            unique_relations.append(r)

    return unique_relations


def build_fix_priority(findings: List[Dict[str, Any]], relations: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    priorities = []
    for f in findings:
        pct = f.get('metrics', {}).get('percent', 0)
        caused_count = sum(1 for r in relations if r['from'] == f['id'] and r['type'] == 'causes')
        if caused_count > 0:
            rank = 1
        elif pct >= 15:
            rank = 1
        elif pct >= 8:
            rank = 2
        elif pct >= 3:
            rank = 3
        else:
            rank = 4

        title_lower = f.get('title', '').lower()
        if 'config' in title_lower or 'param' in title_lower or 'jvm' in title_lower:
            cost = '极低'
        elif 'pool' in title_lower or '连接' in title_lower:
            cost = '低'
        elif 'serialize' in title_lower or '序列化' in title_lower or 'reflect' in title_lower:
            cost = '低'
        elif 'algorithm' in title_lower or '算法' in title_lower:
            cost = '中'
        elif 'architecture' in title_lower or '架构' in title_lower:
            cost = '高'
        else:
            cost = '中'

        priorities.append({
            'rank': rank,
            'finding_id': f['id'],
            'title': f.get('title', ''),
            'expected_benefit': f'-{pct}% CPU' if pct > 0 else '未知',
            'change_cost': cost
        })

    priorities.sort(key=lambda x: x['rank'])
    return priorities[:8]


def main():
    input_path = None
    output_path = None
    summary_text = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] in ('--input', '-i') and i + 1 < len(args):
            input_path = args[i + 1]
            i += 2
        elif args[i] in ('--output', '-o') and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        elif args[i] in ('--summary', '-s') and i + 1 < len(args):
            summary_text = args[i + 1]
            i += 2
        else:
            i += 1

    if not input_path:
        print('用法: python findings_finalize.py --input findings.json --summary "根因总结" [--output findings.json]', file=sys.stderr)
        sys.exit(1)

    if not output_path:
        output_path = input_path

    if not summary_text:
        print('错误: 必须提供 --summary 参数（由大模型生成的根因总结文本）', file=sys.stderr)
        sys.exit(1)

    data = load_findings(input_path)
    findings_list = data.get('findings', [])

    relations = infer_relations(findings_list)
    fix_priority = build_fix_priority(findings_list, relations)

    data['causal_analysis'] = {
        'summary': summary_text,
        'relations': relations,
        'fix_priority': fix_priority
    }

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    print(f'findings_finalize: {len(findings_list)} findings, {len(relations)} relations, summary.length={len(summary_text)}')
    print(f'Updated: {output_path}')


if __name__ == '__main__':
    main()
