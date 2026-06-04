#!/usr/bin/env python3
"""Run a workload under tracemalloc and report allocation diff hotspots."""

from __future__ import annotations

import argparse
import gc
import os
import sys
import tracemalloc

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, load_workload, print_json, result, run_workload


def format_stat(stat: tracemalloc.StatisticDiff) -> dict:
    frame = stat.traceback[-1] if stat.traceback else None
    return {
        "size_diff_bytes": stat.size_diff,
        "size_diff_mib": bytes_to_mib(stat.size_diff),
        "count_diff": stat.count_diff,
        "traceback": [f"{frame.filename}:{frame.lineno}" for frame in stat.traceback[:8]],
        "top_frame": f"{frame.filename}:{frame.lineno}" if frame else "unknown",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run --script workload with tracemalloc and print Top-N allocation diffs.")
    parser.add_argument("--script", required=True, help="Python workload file defining run_workload(iterations).")
    parser.add_argument("--iterations", type=int, default=CONFIG["tracemalloc"]["iterations"])
    parser.add_argument("--nframe", type=int, default=CONFIG["tracemalloc"]["nframe"])
    parser.add_argument("--top", type=int, default=CONFIG["tracemalloc"]["top"])
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        namespace = load_workload(args.script)
        tracemalloc.start(args.nframe)
        gc.collect()
        baseline_current, _ = tracemalloc.get_traced_memory()
        baseline = tracemalloc.take_snapshot()
        workload_result = run_workload(namespace, args.iterations)
        gc.collect()
        current_traced, peak_traced = tracemalloc.get_traced_memory()
        final = tracemalloc.take_snapshot()
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"script": args.script}), args.output)
        return 2
    finally:
        if tracemalloc.is_tracing():
            tracemalloc.stop()

    stats = final.compare_to(baseline, "traceback")
    positive = [format_stat(stat) for stat in stats if stat.size_diff > 0][: args.top]
    total = sum(item["size_diff_bytes"] for item in positive)
    net_size_diff = current_traced - baseline_current
    peak_minus_final = max(0, peak_traced - current_traced)
    min_size = int(CONFIG["tracemalloc"]["min_size_diff"])
    if net_size_diff >= min_size or total >= min_size:
        verdict = "python_allocation_growth_observed"
    elif peak_minus_final >= min_size:
        verdict = "transient_peak_high_but_released"
    else:
        verdict = "inconclusive"
    payload = result(
        "success",
        {
            "script": os.path.abspath(args.script),
            "iterations": args.iterations,
            "summary": {
                "verdict": verdict,
                "top_positive_size_diff_bytes": total,
                "top_positive_size_diff_mib": bytes_to_mib(total),
                "baseline_traced_bytes": baseline_current,
                "baseline_traced_mib": bytes_to_mib(baseline_current),
                "current_traced_bytes": current_traced,
                "current_traced_mib": bytes_to_mib(current_traced),
                "peak_traced_bytes": peak_traced,
                "peak_traced_mib": bytes_to_mib(peak_traced),
                "net_size_diff_bytes": net_size_diff,
                "net_size_diff_mib": bytes_to_mib(net_size_diff),
                "peak_minus_final_bytes": peak_minus_final,
                "peak_minus_final_mib": bytes_to_mib(peak_minus_final),
                "warning": "tracemalloc identifies allocation sites, not retention roots.",
            },
            "alloc_growth": positive,
            "workload_return_repr": repr(workload_result)[:300],
        },
        backend_used="stdlib:tracemalloc",
        degraded_capabilities=[],
        next_steps=[
            "将 allocation hotspots 与 object_growth.py 的增长类型交叉对照。",
            "继续用 retention_chain.py 追为什么对象仍可达。",
            "若 RSS 增长远大于 tracemalloc diff，转 native-leaks.md。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
