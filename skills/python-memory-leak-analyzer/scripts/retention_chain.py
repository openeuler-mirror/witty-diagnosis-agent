#!/usr/bin/env python3
"""Trace gc referrers for leaked candidate objects in a reproducible workload."""

from __future__ import annotations

import argparse
import gc
import inspect
import os
import sys
import types
from collections import Counter, deque
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, error_payload, load_workload, print_json, result, run_workload


def type_name(obj: object) -> str:
    cls = type(obj)
    return f"{cls.__module__}.{cls.__qualname__}"


def is_self_artifact(obj: object) -> bool:
    return isinstance(obj, (types.FrameType, types.TracebackType))


def workload_global_names(workload_ns: dict[str, Any]) -> dict[int, str]:
    return {
        id(value): name
        for name, value in workload_ns.items()
        if not name.startswith("__")
    }


def root_kind(obj: object, workload_ns: dict[str, Any]) -> str | None:
    if obj is workload_ns:
        return "module_global_dict"
    global_names = workload_global_names(workload_ns)
    if id(obj) in global_names:
        return f"module_global:{global_names[id(obj)]}"
    if isinstance(obj, dict):
        for value in workload_ns.values():
            if getattr(value, "__dict__", None) is obj:
                return "object_or_class_attribute_dict"
    if isinstance(obj, types.CellType):
        return "closure_cell"
    if inspect.isframe(obj):
        return "frame_or_generator"
    return None


def short_repr(obj: object) -> str:
    try:
        text = repr(obj)
    except Exception:
        text = f"<{type_name(obj)}>"
    return text[:160]


def find_chain(target: object, workload_ns: dict[str, Any], max_depth: int, max_referrers: int) -> dict[str, Any]:
    ignored_ids = {id(locals()), id(globals())}
    queue = deque([(target, [{"type": type_name(target), "repr": short_repr(target)}])])
    seen = {id(target)}
    while queue:
        obj, path = queue.popleft()
        kind = root_kind(obj, workload_ns)
        if kind:
            return {"root_kind": kind, "chain": path}
        if len(path) > max_depth:
            continue
        try:
            refs = gc.get_referrers(obj)
        except Exception:
            continue
        for ref in refs[:max_referrers]:
            if id(ref) in seen or id(ref) in ignored_ids or is_self_artifact(ref):
                continue
            seen.add(id(ref))
            queue.append((ref, path + [{"type": type_name(ref), "repr": short_repr(ref)}]))
    return {"root_kind": "unknown", "chain": path if "path" in locals() else []}


def direct_workload_container_ref(obj: object, workload_ns: dict[str, Any]) -> bool:
    global_ids = set(workload_global_names(workload_ns))
    try:
        refs = gc.get_referrers(obj)
    except Exception:
        return False
    return any(id(ref) in global_ids for ref in refs)


def select_candidates(
    type_filter: str | None,
    name_contains: str | None,
    samples: int,
    workload_ns: dict[str, Any],
) -> list[object]:
    gc.collect()
    preferred = []
    fallback = []
    for obj in gc.get_objects():
        name = type_name(obj)
        if type_filter and name != type_filter:
            continue
        if name_contains and name_contains not in name:
            continue
        if direct_workload_container_ref(obj, workload_ns):
            preferred.append(obj)
        else:
            fallback.append(obj)
        if len(preferred) >= samples:
            break
    return (preferred + fallback)[:samples]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run --script workload then trace referrers for candidate objects.")
    parser.add_argument("--script", required=True, help="Python workload file defining run_workload(iterations).")
    parser.add_argument("--iterations", type=int, default=CONFIG["retention"]["iterations"])
    parser.add_argument("--type-filter", help="Exact module.qualname candidate type from object_growth.py.")
    parser.add_argument("--name-contains", help="Fallback substring match for candidate type name.")
    parser.add_argument("--samples", type=int, default=CONFIG["retention"]["samples"])
    parser.add_argument("--max-depth", type=int, default=CONFIG["retention"]["max_depth"])
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        namespace = load_workload(args.script)
        run_workload(namespace, args.iterations)
        candidates = select_candidates(args.type_filter, args.name_contains, args.samples, namespace)
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"script": args.script}), args.output)
        return 2

    chains = [
        find_chain(candidate, namespace, args.max_depth, int(CONFIG["retention"]["max_referrers"]))
        for candidate in candidates
    ]
    root_summary = Counter(chain["root_kind"] for chain in chains)
    verdict = "retention_chain_observed" if candidates else "no_candidate_objects"
    payload = result(
        "success" if candidates else "partial",
        {
            "script": os.path.abspath(args.script),
            "iterations": args.iterations,
            "candidate_count_sampled": len(candidates),
            "summary": {"verdict": verdict, "root_kind_summary": dict(root_summary)},
            "chains": chains,
        },
        backend_used="stdlib:gc.get_referrers",
        degraded_capabilities=["objgraph not required; output is textual and depth-limited."],
        next_steps=[
            "若 root_kind 指向 module_global:<name> 或 cache，查看 root-cause-patterns.md。",
            "生产环境默认不做反事实干预；沙箱中可运行 reachability_probe.py --allow-mutation。",
            "多条 root_kind 发散时保留多假设，避免过早收敛。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
