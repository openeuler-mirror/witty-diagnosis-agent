#!/usr/bin/env python3
"""Summarize workload-level leak semantics from module globals."""

from __future__ import annotations

import argparse
import asyncio
import gc
import inspect
import os
import sys
import types
import weakref
from collections import Counter
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, load_workload, print_json, result, run_workload


CONTAINER_TYPES = (dict, list, set, tuple)


def type_name(obj: object) -> str:
    cls = type(obj)
    return f"{cls.__module__}.{cls.__qualname__}"


def safe_len(obj: object) -> int | None:
    try:
        return len(obj)  # type: ignore[arg-type]
    except Exception:
        return None


def safe_size(obj: object) -> int:
    try:
        return sys.getsizeof(obj)
    except Exception:
        return 0


def short_repr(obj: object, limit: int = 160) -> str:
    try:
        text = repr(obj)
    except Exception:
        text = f"<{type_name(obj)}>"
    return text[:limit]


def cache_info(value: object) -> dict[str, Any] | None:
    reader = getattr(value, "cache_info", None)
    if not callable(reader):
        return None
    try:
        info = reader()
    except Exception:
        return None
    return info._asdict() if hasattr(info, "_asdict") else dict(info)


def is_user_global(name: str, value: object) -> bool:
    if name.startswith("__"):
        return False
    if inspect.ismodule(value):
        return False
    return True


def callable_role(value: object) -> str | None:
    if inspect.isfunction(value):
        if getattr(value, "__closure__", None):
            return "function_with_closure"
        if cache_info(value) is not None:
            return "cache_function"
        return "function"
    if inspect.ismethod(value):
        return "bound_method"
    return None


def item_role(item: object) -> str:
    if inspect.ismethod(item):
        return "bound_method"
    if inspect.isfunction(item):
        return "function_with_closure" if getattr(item, "__closure__", None) else "function"
    if inspect.isgenerator(item):
        return "generator"
    if isinstance(item, asyncio.Task):
        return "asyncio_task"
    if isinstance(item, weakref.finalize):
        return "weakref_finalize"
    return type_name(item)


def iter_container_items(value: object, limit: int) -> list[object]:
    try:
        if isinstance(value, dict):
            return list(value.values())[:limit]
        if isinstance(value, (list, tuple, set)):
            return list(value)[:limit]
    except Exception:
        return []
    return []


def closure_summary(func: object) -> dict[str, Any] | None:
    closure = getattr(func, "__closure__", None)
    if not closure:
        return None
    cells = []
    for cell in closure:
        try:
            content = cell.cell_contents
        except ValueError:
            cells.append({"empty": True})
            continue
        cells.append(
            {
                "type": type_name(content),
                "len": safe_len(content),
                "shallow_size_bytes": safe_size(content),
                "repr": short_repr(content),
            }
        )
    return {
        "qualname": getattr(func, "__qualname__", None),
        "cell_count": len(cells),
        "cells": cells,
    }


def bound_method_summary(method: object) -> dict[str, Any] | None:
    if not inspect.ismethod(method):
        return None
    owner = getattr(method, "__self__", None)
    func = getattr(method, "__func__", None)
    return {
        "method": getattr(func, "__qualname__", short_repr(method)),
        "self_type": type_name(owner) if owner is not None else None,
        "self_repr": short_repr(owner) if owner is not None else None,
    }


def generator_summary(generator: object) -> dict[str, Any] | None:
    if not inspect.isgenerator(generator):
        return None
    frame = generator.gi_frame
    locals_summary = {}
    if frame is not None:
        for key, value in list(frame.f_locals.items())[:8]:
            locals_summary[key] = {
                "type": type_name(value),
                "len": safe_len(value),
                "shallow_size_bytes": safe_size(value),
            }
    return {
        "name": generator.gi_code.co_qualname,
        "state": inspect.getgeneratorstate(generator),
        "frame_locals": locals_summary,
    }


def task_summary(task: object) -> dict[str, Any] | None:
    if not isinstance(task, asyncio.Task):
        return None
    coro = task.get_coro()
    frame = getattr(coro, "cr_frame", None)
    locals_summary = {}
    if frame is not None:
        for key, value in list(frame.f_locals.items())[:8]:
            locals_summary[key] = {
                "type": type_name(value),
                "len": safe_len(value),
                "shallow_size_bytes": safe_size(value),
            }
    return {
        "done": task.done(),
        "cancelled": task.cancelled(),
        "coro": getattr(coro, "__qualname__", type_name(coro)),
        "frame_locals": locals_summary,
    }


def container_semantics(name: str, value: object, before_len: int | None, sample_limit: int) -> dict[str, Any]:
    after_len = safe_len(value)
    items = iter_container_items(value, sample_limit)
    role_counts = Counter(item_role(item) for item in items)
    bound_methods = [bound_method_summary(item) for item in items if inspect.ismethod(item)]
    closures = [closure_summary(item) for item in items if inspect.isfunction(item) and getattr(item, "__closure__", None)]
    generators = [generator_summary(item) for item in items if inspect.isgenerator(item)]
    tasks = [task_summary(item) for item in items if isinstance(item, asyncio.Task)]
    return {
        "name": name,
        "type": type_name(value),
        "len_before": before_len,
        "len_after": after_len,
        "len_delta": after_len - before_len if isinstance(before_len, int) and isinstance(after_len, int) else None,
        "shallow_size_bytes": safe_size(value),
        "shallow_size_mib": bytes_to_mib(safe_size(value)),
        "item_role_counts": dict(role_counts),
        "sample_items": [
            {
                "role": item_role(item),
                "type": type_name(item),
                "repr": short_repr(item),
            }
            for item in items[: min(3, len(items))]
        ],
        "bound_methods": [item for item in bound_methods if item][:3],
        "closures": [item for item in closures if item][:3],
        "generators": [item for item in generators if item][:3],
        "asyncio_tasks": [item for item in tasks if item][:3],
    }


def global_snapshot(namespace: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = {}
    for name, value in namespace.items():
        if not is_user_global(name, value):
            continue
        rows[name] = {
            "type": type_name(value),
            "len": safe_len(value),
            "cache_info": cache_info(value),
            "callable_role": callable_role(value),
        }
    return rows


def cache_delta(before: dict[str, Any] | None, after: dict[str, Any] | None) -> int | None:
    if not isinstance(before, dict) or not isinstance(after, dict):
        return None
    before_size = before.get("currsize")
    after_size = after.get("currsize")
    if isinstance(before_size, int) and isinstance(after_size, int):
        return after_size - before_size
    return None


def summarize_globals(
    namespace: dict[str, Any],
    before: dict[str, dict[str, Any]],
    after: dict[str, dict[str, Any]],
    sample_limit: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    globals_rows = []
    cache_rows = []
    for name, meta in after.items():
        value = namespace.get(name)
        before_meta = before.get(name, {})
        if value is None:
            continue
        cache_after = meta.get("cache_info")
        cache_before = before_meta.get("cache_info")
        if isinstance(cache_after, dict):
            delta = cache_delta(cache_before, cache_after)
            cache_rows.append(
                {
                    "name": name,
                    "before": cache_before,
                    "after": cache_after,
                    "currsize_delta": delta,
                    "unbounded": cache_after.get("maxsize") is None,
                }
            )
        if isinstance(value, CONTAINER_TYPES):
            globals_rows.append(container_semantics(name, value, before_meta.get("len"), sample_limit))
        elif meta.get("callable_role"):
            globals_rows.append(
                {
                    "name": name,
                    "type": meta.get("type"),
                    "callable_role": meta.get("callable_role"),
                    "cache_info_before": cache_before,
                    "cache_info_after": cache_after,
                    "cache_currsize_delta": cache_delta(cache_before, cache_after),
                    "closure": closure_summary(value),
                }
            )
    return globals_rows, cache_rows


def signal_score(row: dict[str, Any]) -> int:
    score = 0
    delta = row.get("len_delta")
    if isinstance(delta, int):
        score += max(0, delta)
    cache_delta_value = row.get("cache_currsize_delta")
    if isinstance(cache_delta_value, int):
        score += max(0, cache_delta_value)
    roles = row.get("item_role_counts")
    if isinstance(roles, dict):
        for role in ("bound_method", "function_with_closure", "generator", "asyncio_task", "weakref_finalize"):
            score += int(roles.get(role, 0)) * 2
    if row.get("closures"):
        score += 5
    if row.get("bound_methods"):
        score += 5
    return score


def classify_signal(row: dict[str, Any]) -> list[str]:
    labels = []
    roles = row.get("item_role_counts")
    if isinstance(roles, dict):
        if roles.get("bound_method"):
            labels.append("global_registry_retains_bound_methods")
        if roles.get("function_with_closure"):
            labels.append("global_table_retains_closures")
        if roles.get("generator"):
            labels.append("unclosed_generators_retain_frames")
        if roles.get("asyncio_task"):
            labels.append("pending_asyncio_tasks_retain_frames")
        if roles.get("weakref_finalize"):
            labels.append("weakref_finalize_callbacks_retained")
    if row.get("cache_currsize_delta"):
        labels.append("callable_cache_growth")
    if row.get("len_delta") and not labels:
        labels.append("global_container_growth")
    return labels


def dominant_signals(globals_rows: list[dict[str, Any]], cache_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for row in globals_rows:
        labels = classify_signal(row)
        score = signal_score(row)
        if score <= 0 and not labels:
            continue
        rows.append(
            {
                "name": row.get("name"),
                "type": row.get("type"),
                "score": score,
                "labels": labels,
                "len_delta": row.get("len_delta"),
                "len_after": row.get("len_after"),
                "item_role_counts": row.get("item_role_counts"),
            }
        )
    for cache in cache_rows:
        delta = cache.get("currsize_delta")
        if isinstance(delta, int) and delta > 0:
            rows.append(
                {
                    "name": cache.get("name"),
                    "type": "cache_function",
                    "score": delta,
                    "labels": ["unbounded_cache_growth" if cache.get("unbounded") else "cache_growth"],
                    "currsize_delta": delta,
                    "after": cache.get("after"),
                }
            )
    rows.sort(key=lambda item: item.get("score", 0), reverse=True)
    return rows[:8]


def gc_semantics() -> dict[str, Any]:
    garbage = list(gc.garbage)
    type_counts = Counter(type_name(item) for item in garbage[:1000])
    return {
        "debug_flags": gc.get_debug(),
        "garbage_len": len(garbage),
        "garbage_type_counts": dict(type_counts.most_common(8)),
        "debug_saveall_active": bool(gc.get_debug() & gc.DEBUG_SAVEALL),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run --script workload and summarize semantic leak signals.")
    parser.add_argument("--script", required=True, help="Python workload file defining run_workload(iterations).")
    parser.add_argument("--iterations", type=int, default=CONFIG["object_growth"]["iterations"])
    parser.add_argument("--sample-limit", type=int, default=20)
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        namespace = load_workload(args.script)
        setup = namespace.get("setup")
        if callable(setup):
            setup()
        before = global_snapshot(namespace)
        workload_result = run_workload(namespace, args.iterations)
        after = global_snapshot(namespace)
        globals_rows, cache_rows = summarize_globals(namespace, before, after, args.sample_limit)
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"script": args.script}), args.output)
        return 2

    signals = dominant_signals(globals_rows, cache_rows)
    verdict = "semantic_leak_signals_observed" if signals else "no_semantic_signal"
    payload = result(
        "success" if signals else "partial",
        {
            "script": os.path.abspath(args.script),
            "iterations": args.iterations,
            "summary": {
                "verdict": verdict,
                "dominant_signals": signals[:3],
                "competing_signal_count": max(0, len(signals) - 1),
            },
            "global_semantics": globals_rows,
            "cache_semantics": cache_rows,
            "gc_semantics": gc_semantics(),
            "workload_return_repr": repr(workload_result)[:500],
        },
        backend_used="stdlib:module-introspection",
        degraded_capabilities=[
            "Semantic probe requires a reproducible workload script; live PID remains external-observation only.",
            "Deep retained size still requires optional Pympler or Memray for native allocations.",
        ],
        next_steps=[
            "Use semantic labels to choose the first root-cause hypothesis before asking for more logs.",
            "Cross-check dominant semantic signals with object_growth.py, tracemalloc_probe.py, and retention_chain.py.",
            "If only RSS evidence exists, keep confidence capped and do not claim a confirmed Python root cause.",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
