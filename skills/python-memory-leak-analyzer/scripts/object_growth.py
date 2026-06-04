#!/usr/bin/env python3
"""Run a reproducible workload and summarize Python object growth."""

from __future__ import annotations

import argparse
import gc
import importlib.util
import os
import sys
from collections import Counter
from collections.abc import Callable
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, load_workload, print_json, result, run_workload


CONTAINER_TYPES = (dict, list, set, tuple)


def type_name(obj: object) -> str:
    cls = type(obj)
    return f"{cls.__module__}.{cls.__qualname__}"


def shallow_size(obj: object) -> int:
    try:
        return sys.getsizeof(obj)
    except Exception:
        return 0


def resolve_size_backend(requested: str) -> tuple[str, Callable[[object], int], list[str]]:
    degraded: list[str] = []
    pympler_available = False
    if requested in {"auto", "pympler"}:
        try:
            pympler_available = importlib.util.find_spec("pympler.asizeof") is not None
        except ModuleNotFoundError:
            pympler_available = False
    if requested in {"auto", "pympler"} and pympler_available:
        try:
            from pympler import asizeof  # type: ignore

            def pympler_size(obj: object) -> int:
                try:
                    return int(asizeof.asizeof(obj))
                except Exception:
                    return shallow_size(obj)

            return "pympler.asizeof", pympler_size, degraded
        except Exception as exc:
            degraded.append(f"pympler.asizeof unavailable at runtime: {exc}; falling back to shallow sys.getsizeof.")
    elif requested == "pympler":
        degraded.append("pympler not installed; falling back to shallow sys.getsizeof.")
    else:
        degraded.append("pympler deep size not used; shallow bytes may undercount nested containers.")
    return "stdlib:sys.getsizeof", shallow_size, degraded


def snapshot(top_containers: int, size_func: Callable[[object], int]) -> dict[str, Any]:
    gc.collect()
    counts: Counter[str] = Counter()
    sizes: Counter[str] = Counter()
    containers: list[dict[str, Any]] = []
    for obj in gc.get_objects():
        name = type_name(obj)
        counts[name] += 1
        object_size = size_func(obj)
        sizes[name] += object_size
        if isinstance(obj, CONTAINER_TYPES):
            try:
                length = len(obj)
            except Exception:
                length = -1
            if length >= 0:
                containers.append(
                    {
                        "type": name,
                        "len": length,
                        "size_bytes": object_size,
                        "size_mib": bytes_to_mib(object_size),
                        "repr": repr(obj)[:160],
                    }
                )
    containers.sort(key=lambda item: (item["len"], item["size_bytes"]), reverse=True)
    return {"counts": counts, "sizes": sizes, "big_containers": containers[:top_containers]}


def cache_infos(namespace: dict[str, Any]) -> dict[str, dict[str, Any]]:
    infos: dict[str, dict[str, Any]] = {}
    for name, value in namespace.items():
        cache_info = getattr(value, "cache_info", None)
        if callable(cache_info):
            try:
                info = cache_info()
                infos[name] = info._asdict() if hasattr(info, "_asdict") else dict(info)
            except Exception:
                continue
    return infos


def diff(before: dict[str, Any], after: dict[str, Any], top: int, size_label: str) -> list[dict[str, Any]]:
    keys = set(before["counts"]) | set(after["counts"])
    rows: list[dict[str, Any]] = []
    for key in keys:
        count_delta = after["counts"].get(key, 0) - before["counts"].get(key, 0)
        bytes_delta = after["sizes"].get(key, 0) - before["sizes"].get(key, 0)
        if count_delta or bytes_delta:
            rows.append(
                {
                    "type": key,
                    "count_before": before["counts"].get(key, 0),
                    "count_after": after["counts"].get(key, 0),
                    "count_delta": count_delta,
                    "size_backend": size_label,
                    "bytes_before": before["sizes"].get(key, 0),
                    "bytes_after": after["sizes"].get(key, 0),
                    "bytes_delta": bytes_delta,
                    "mib_delta": bytes_to_mib(bytes_delta),
                }
            )
    rows.sort(key=lambda item: (item["bytes_delta"], item["count_delta"]), reverse=True)
    return rows[:top]


def verdict(rows: list[dict[str, Any]], config: dict[str, Any]) -> dict[str, Any]:
    if not rows:
        return {"verdict": "no_tracked_growth", "reason": "gc tracked objects did not grow"}
    top = rows[0]
    min_count = int(config["object_growth"]["min_count_delta"])
    min_bytes = int(config["object_growth"]["min_bytes_delta"])
    if top["count_delta"] >= min_count or top["bytes_delta"] >= min_bytes:
        return {
            "verdict": "python_object_growth_observed",
            "primary_candidate": top["type"],
            "reason": "dominant tracked type grew during workload",
        }
    return {
        "verdict": "inconclusive",
        "primary_candidate": top["type"],
        "reason": "growth below configured thresholds",
    }


def cache_growth(before: dict[str, dict[str, Any]], after: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for name, after_info in after.items():
        before_info = before.get(name, {})
        before_size = before_info.get("currsize")
        after_size = after_info.get("currsize")
        delta = None
        if isinstance(before_size, int) and isinstance(after_size, int):
            delta = after_size - before_size
        rows.append(
            {
                "name": name,
                "before": before_info,
                "after": after_info,
                "currsize_delta": delta,
                "unbounded": after_info.get("maxsize") is None,
            }
        )
    return rows


def parse_checkpoints(raw: str, iterations: int) -> list[int]:
    if raw.strip().lower() in {"", "none", "off", "false"}:
        return []
    values: set[int] = set()
    for item in raw.split(","):
        token = item.strip()
        if not token:
            continue
        try:
            if token.endswith("%"):
                value = max(1, int(round(iterations * float(token[:-1]) / 100.0)))
            else:
                number = float(token)
                value = max(1, int(round(iterations * number if number <= 1 else number)))
        except ValueError:
            continue
        values.add(min(value, iterations))
    if values and iterations not in values:
        values.add(iterations)
    return sorted(values)


def snapshot_totals(point: dict[str, Any], size_label: str) -> dict[str, Any]:
    total_count = sum(point["counts"].values())
    total_bytes = sum(point["sizes"].values())
    top_type = None
    top_bytes = None
    if point["sizes"]:
        top_type, top_bytes = point["sizes"].most_common(1)[0]
    return {
        "total_tracked_count": total_count,
        "total_tracked_bytes": total_bytes,
        "total_tracked_mib": bytes_to_mib(total_bytes),
        "size_backend": size_label,
        "top_type": top_type,
        "top_type_bytes": top_bytes,
        "top_type_mib": bytes_to_mib(top_bytes),
    }


def classify_checkpoint_trend(points: list[dict[str, Any]], min_bytes: int) -> dict[str, Any]:
    if len(points) < 2:
        return {"verdict": "not_collected", "reason": "fewer than two checkpoints"}
    values = [item["total_tracked_bytes"] for item in points]
    first = values[0]
    final = values[-1]
    peak = max(values)
    tail = values[max(0, len(values) * 2 // 3) :]
    tail_delta = max(tail) - min(tail) if tail else 0
    monotonic = all(later >= earlier for earlier, later in zip(values, values[1:]))
    if peak - final >= min_bytes and final <= first + min_bytes:
        verdict = "released_after_peak"
        reason = "tracked heap reached a peak but was mostly released by the final checkpoint"
    elif monotonic and final - first >= min_bytes:
        verdict = "monotonic_growth"
        reason = "tracked heap grew monotonically across checkpoints"
    elif final - first >= min_bytes and tail_delta <= max(min_bytes, int((peak - first) * 0.15)):
        verdict = "plateau"
        reason = "tracked heap grew then stabilized near the tail checkpoints"
    else:
        verdict = "workload_coupled_or_noisy"
        reason = "checkpoint trend did not prove monotonic retained growth"
    return {
        "verdict": verdict,
        "reason": reason,
        "first_tracked_bytes": first,
        "final_tracked_bytes": final,
        "peak_tracked_bytes": peak,
        "net_tracked_growth_bytes": final - first,
        "peak_minus_final_bytes": peak - final,
        "net_tracked_growth_mib": bytes_to_mib(final - first),
        "peak_minus_final_mib": bytes_to_mib(peak - final),
    }


def checkpoint_trend(
    script_path: str,
    checkpoints: list[int],
    size_func: Callable[[object], int],
    size_label: str,
    top_containers: int,
) -> dict[str, Any]:
    if not checkpoints:
        return {"summary": {"verdict": "not_collected", "reason": "checkpoint collection disabled"}, "points": []}
    namespace = load_workload(script_path)
    setup = namespace.get("setup")
    if callable(setup):
        setup()
    workload = namespace.get("run_workload")
    if not callable(workload):
        raise ValueError("workload script must define run_workload(iterations)")
    baseline = snapshot(top_containers, size_func)
    points = [{"checkpoint": "baseline", "iterations_argument": 0, **snapshot_totals(baseline, size_label)}]
    last_result: Any = None
    for checkpoint in checkpoints:
        last_result = workload(checkpoint)
        point = snapshot(top_containers, size_func)
        points.append({"checkpoint": checkpoint, "iterations_argument": checkpoint, **snapshot_totals(point, size_label)})
    summary = classify_checkpoint_trend(points, int(CONFIG["object_growth"]["min_bytes_delta"]))
    return {
        "summary": summary,
        "mode": "cumulative_argument_no_reset",
        "points": points,
        "workload_return_repr": repr(last_result)[:300],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run --script workload and compare gc-tracked Python object growth.")
    parser.add_argument("--script", required=True, help="Python workload file defining run_workload(iterations).")
    parser.add_argument("--iterations", type=int, default=CONFIG["object_growth"]["iterations"])
    parser.add_argument("--top", type=int, default=CONFIG["object_growth"]["top"])
    parser.add_argument(
        "--checkpoints",
        default="25%,50%,75%,100%",
        help="Comma-separated checkpoint arguments, percentages, or fractions. Use 'none' to disable.",
    )
    parser.add_argument(
        "--size-backend",
        choices=("auto", "shallow", "pympler"),
        default="auto",
        help="Object size backend: auto uses pympler.asizeof when installed, otherwise sys.getsizeof.",
    )
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        size_backend, size_func, degraded = resolve_size_backend(args.size_backend)
        namespace = load_workload(args.script)
        cache_before = cache_infos(namespace)
        before = snapshot(int(CONFIG["object_growth"]["big_container_top"]), size_func)
        workload_result = run_workload(namespace, args.iterations)
        after = snapshot(int(CONFIG["object_growth"]["big_container_top"]), size_func)
        cache_after = cache_infos(namespace)
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"script": args.script}), args.output)
        return 2

    checkpoint_payload: dict[str, Any]
    try:
        checkpoints = parse_checkpoints(args.checkpoints, args.iterations)
        checkpoint_payload = checkpoint_trend(
            args.script,
            checkpoints,
            size_func,
            size_backend,
            int(CONFIG["object_growth"]["big_container_top"]),
        )
    except Exception as exc:
        degraded.append(f"checkpoint trend unavailable: {exc}")
        checkpoint_payload = {"summary": {"verdict": "not_collected", "reason": str(exc)}, "points": []}

    rows = diff(before, after, args.top, size_backend)
    summary = verdict(rows, CONFIG)
    caches = cache_growth(cache_before, cache_after)
    growing_caches = [item for item in caches if isinstance(item.get("currsize_delta"), int) and item["currsize_delta"] > 0]
    if growing_caches and summary["verdict"] == "inconclusive":
        summary = {
            "verdict": "python_cache_growth_observed",
            "primary_candidate": f"cache:{growing_caches[0]['name']}",
            "reason": "workload exposed cache_info().currsize growth",
        }
    payload = result(
        "success",
        {
            "script": os.path.abspath(args.script),
            "iterations": args.iterations,
            "size_backend": size_backend,
            "summary": summary,
            "type_growth": rows,
            "cache_growth": caches,
            "checkpoint_trend": checkpoint_payload,
            "big_containers_after": after["big_containers"],
            "workload_return_repr": repr(workload_result)[:300],
        },
        backend_used=f"stdlib:gc+{size_backend}",
        degraded_capabilities=degraded,
        next_steps=[
            "将 primary_candidate 传给 retention_chain.py --type-filter 追保留者。",
            "并行运行 tracemalloc_probe.py 交叉验证分配栈；分配点不等于保留点。",
            "若 type_growth 解释不了 RSS 增长，考虑 native/arena 或未被 gc 跟踪的大对象。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
