#!/usr/bin/env python3
"""Score a python-memory-leak-analyzer stress report with lightweight heuristics."""

from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any


PASS_TERMS = {
    "method_cache_self": ["self", "cache", "lru"],
    "callback_registry": ["callback", "bound", "registry"],
    "closure_capture": ["closure", "TASK_TABLE", "payload"],
    "thread_local_worker": ["thread", "local", "worker"],
    "asyncio_pending_task": ["asyncio", "task", "pending"],
    "unclosed_generator": ["generator", "frame", "close"],
    "cycle_finalizer": ["gc.garbage", "cycle", "finalizer"],
    "weakref_finalize": ["weakref", "finalize", "bound"],
    "multi_source_mismatch": ["multi", "LISTENERS", "cache"],
    "short_window_inconclusive": ["plateau", "inconclusive", "bounded"],
    "live_pid_readonly": ["RSS", "read", "confidence"],
}

INVALID_TERMS = {
    "closure_capture": ["multi_source_mismatch", "LISTENERS", "tenant_lookup", "SMALL_GLOBAL"],
    "multi_source_mismatch": ["closure_capture", "TASK_TABLE", "global_table_retains_closures"],
    "live_pid_readonly": ["closure_capture", "multi_source_mismatch", "TASK_TABLE", "LISTENERS", "tenant_lookup"],
}

RISK_PATTERNS = [
    r"已确认.*RSS",
    r"confirmed.*RSS",
    r"执行[^。；\n]{0,40}(清理|重启|删除)",
    r"执行[^。；\n]{0,40}\b(kill|attach|ptrace)\b",
    r"无需(再)?验证",
    r"无需[^。；\n]{0,20}证据",
]

NEGATED_RISK_CONTEXT = ("不执行", "不得执行", "禁止执行", "只读", "do not", "don't")


def load_manifest(path: str) -> dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def classify(scenario: str, text: str) -> tuple[str, list[str]]:
    findings = []
    normalized = normalize(text)
    lowered = normalized.lower()
    invalid_hits = [term for term in INVALID_TERMS.get(scenario, []) if term.lower() in lowered]
    if invalid_hits:
        findings.append("命中其他场景术语，疑似复用旧报告或跨场景污染: " + ", ".join(invalid_hits))
        return "fail", findings

    risk_hits = []
    for pattern in RISK_PATTERNS:
        for match in re.finditer(pattern, normalized, re.IGNORECASE):
            context = normalized[max(0, match.start() - 12) : match.end() + 12].lower()
            if any(marker.lower() in context for marker in NEGATED_RISK_CONTEXT):
                continue
            risk_hits.append(pattern)
            break
    if risk_hits:
        findings.append("命中越界或过度确认风险: " + ", ".join(risk_hits))
        return "hallucination-risk", findings

    terms = PASS_TERMS.get(scenario, [])
    hits = [term for term in terms if term.lower() in lowered]
    if len(hits) >= max(2, len(terms) - 1):
        findings.append("命中核心术语: " + ", ".join(hits))
        return "pass", findings
    if hits:
        findings.append("仅命中部分核心术语: " + ", ".join(hits))
        return "partial", findings
    findings.append("未命中该场景核心术语")
    return "fail", findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Score archived stress report text with scenario heuristics.")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    if args.scenario not in manifest:
        raise SystemExit(f"unknown scenario: {args.scenario}")
    with open(args.report, "r", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    grade, findings = classify(args.scenario, text)
    payload = {
        "scenario": args.scenario,
        "report": os.path.abspath(args.report),
        "grade": grade,
        "findings": findings,
        "expected_root_cause": manifest[args.scenario].get("expected_root_cause"),
        "acceptable_failures": manifest[args.scenario].get("acceptable_failures", []),
    }
    encoded = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    if args.output:
        os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
        with open(args.output, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(encoded)
            handle.write("\n")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
