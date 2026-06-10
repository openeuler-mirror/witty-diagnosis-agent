#!/usr/bin/env python3
"""Static or controlled reachability counterfactual probe for workload leaks."""

from __future__ import annotations

import argparse
import gc
import os
import sys
import weakref
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, error_payload, load_workload, print_json, result, run_workload


def type_name(obj: object) -> str:
    cls = type(obj)
    return f"{cls.__module__}.{cls.__qualname__}"


def collect_candidates(type_filter: str | None, name_contains: str | None) -> list[object]:
    gc.collect()
    candidates = []
    for obj in gc.get_objects():
        name = type_name(obj)
        if type_filter and name != type_filter:
            continue
        if name_contains and name_contains not in name:
            continue
        candidates.append(obj)
    return candidates


def cache_info(value: object) -> dict[str, Any] | None:
    reader = getattr(value, "cache_info", None)
    if not callable(reader):
        return None
    try:
        info = reader()
    except Exception:
        return None
    return info._asdict() if hasattr(info, "_asdict") else dict(info)


def describe_named_global(namespace: dict[str, Any], global_name: str) -> dict[str, Any]:
    if global_name not in namespace:
        return {"exists": False}
    value = namespace[global_name]
    length = None
    try:
        length = len(value) if hasattr(value, "__len__") else None
    except Exception:
        length = None
    return {
        "exists": True,
        "type": type_name(value),
        "len": length,
        "cache_info": cache_info(value),
    }


def global_reclaimed_ratio(before: dict[str, Any], after: dict[str, Any]) -> float | None:
    before_cache = before.get("cache_info")
    after_cache = after.get("cache_info")
    if isinstance(before_cache, dict) and isinstance(after_cache, dict):
        before_size = before_cache.get("currsize")
        after_size = after_cache.get("currsize")
        if isinstance(before_size, int) and isinstance(after_size, int) and before_size > 0:
            return max(0.0, (before_size - after_size) / before_size)

    before_len = before.get("len")
    after_len = after.get("len")
    if isinstance(before_len, int) and isinstance(after_len, int) and before_len > 0:
        return max(0.0, (before_len - after_len) / before_len)

    if before.get("exists") and not after.get("exists"):
        return 1.0
    return None


def clear_named_global(namespace: dict[str, Any], global_name: str) -> dict[str, Any]:
    if global_name not in namespace:
        raise KeyError(global_name)
    value = namespace[global_name]
    before = describe_named_global(namespace, global_name)
    if hasattr(value, "cache_clear") and callable(value.cache_clear):
        value.cache_clear()
        action = "cache_clear"
    elif hasattr(value, "clear") and callable(value.clear):
        value.clear()
        action = "clear"
    else:
        namespace[global_name] = None
        action = "set_none"
    after = describe_named_global(namespace, global_name)
    return {
        "global_name": global_name,
        "action": action,
        "before": before,
        "after": after,
        "global_reclaimed_ratio": global_reclaimed_ratio(before, after),
    }


def weakrefs_for(objects: list[object]) -> tuple[list[weakref.ReferenceType], int]:
    refs = []
    unsupported = 0
    for obj in objects:
        try:
            refs.append(weakref.ref(obj))
        except TypeError:
            unsupported += 1
    return refs, unsupported


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate candidate reachability with static or approved mutation mode.")
    parser.add_argument("--script", required=True, help="Python workload file defining run_workload(iterations).")
    parser.add_argument("--iterations", type=int, default=CONFIG["reachability"]["iterations"])
    parser.add_argument("--type-filter", help="Exact module.qualname candidate type.")
    parser.add_argument("--name-contains", help="Fallback substring match for candidate type name.")
    parser.add_argument("--global-name", help="Global container/cache to clear when --allow-mutation is set.")
    parser.add_argument("--allow-mutation", action="store_true", help="Approve sandbox counterfactual mutation.")
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        namespace = load_workload(args.script)
        run_workload(namespace, args.iterations)
        before = collect_candidates(args.type_filter, args.name_contains)
        before_count = len(before)
        refs, unsupported = weakrefs_for(before[:100])
        del before
        mutation_record = None
        if args.allow_mutation:
            if not args.global_name:
                raise ValueError("--global-name is required with --allow-mutation")
            mutation_record = clear_named_global(namespace, args.global_name)
        for _ in range(int(CONFIG["reachability"]["gc_rounds"])):
            gc.collect()
        after = collect_candidates(args.type_filter, args.name_contains)
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"script": args.script}), args.output)
        return 2

    live_refs = sum(1 for ref in refs if ref() is not None)
    after_count = len(after)
    candidate_reclaimed_ratio = 0.0 if before_count == 0 else max(0.0, (before_count - after_count) / before_count)
    target_reclaimed_ratio = None
    if mutation_record:
        raw_ratio = mutation_record.get("global_reclaimed_ratio")
        if isinstance(raw_ratio, (int, float)):
            target_reclaimed_ratio = float(raw_ratio)
    reclaimed_ratio = max(candidate_reclaimed_ratio, target_reclaimed_ratio or 0.0)
    if not args.allow_mutation:
        verdict = "static_only"
        confidence_cap = "weak"
    elif reclaimed_ratio >= float(CONFIG["reachability"]["reclaimed_ratio_confirm"]):
        verdict = "counterfactual_confirmed"
        confidence_cap = "strong"
    elif before_count > after_count:
        verdict = "counterfactual_partial"
        confidence_cap = "medium"
    else:
        verdict = "counterfactual_rejected"
        confidence_cap = "weak"

    payload = result(
        "success" if args.allow_mutation else "partial",
        {
            "script": os.path.abspath(args.script),
            "iterations": args.iterations,
            "summary": {
                "verdict": verdict,
                "confidence_cap": confidence_cap,
                "before_count": before_count,
                "after_count": after_count,
                "reclaimed_ratio": round(reclaimed_ratio, 3),
                "candidate_reclaimed_ratio": round(candidate_reclaimed_ratio, 3),
                "target_reclaimed_ratio": round(target_reclaimed_ratio, 3) if target_reclaimed_ratio is not None else None,
                "live_weakrefs_after": live_refs,
                "weakref_unsupported_samples": unsupported,
            },
            "mutation_record": mutation_record,
        },
        backend_used="stdlib:gc+weakref",
        degraded_capabilities=[] if args.allow_mutation else ["Mutation not approved; static reachability only, confidence capped at weak."],
        next_steps=[
            "若 counterfactual_confirmed，修复后复跑 monitor/object/tracemalloc 量化增长停止。",
            "若 static_only，将结论写成主导假设而非确认根因。",
            "若 rejected/partial，回到 retention_chain.py 寻找其他保留路径。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
