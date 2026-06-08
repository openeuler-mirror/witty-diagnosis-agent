#!/usr/bin/env python3
"""Correlate RSS, /proc, Python heap, allocation, semantic and retention evidence."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, print_json, result


def load_payload(path: str | None, label: str) -> tuple[dict[str, Any] | None, str | None]:
    if not path:
        return None, label
    if not os.path.isfile(path):
        raise FileNotFoundError(f"{label}: {path}")
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle), None


def results(payload: dict[str, Any] | None) -> dict[str, Any]:
    if not isinstance(payload, dict):
        return {}
    value = payload.get("results")
    return value if isinstance(value, dict) else payload


def nested(data: dict[str, Any], *keys: str) -> Any:
    current: Any = data
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def positive_sum(rows: list[dict[str, Any]], key: str) -> int:
    total = 0
    for row in rows:
        value = row.get(key)
        if isinstance(value, (int, float)) and value > 0:
            total += int(value)
    return total


def safe_ratio(numerator: int | float | None, denominator: int | float | None) -> float | None:
    if numerator is None or denominator is None or denominator <= 0:
        return None
    return round(float(numerator) / float(denominator), 4)


def monitor_net(monitor: dict[str, Any], key: str) -> int | None:
    summary = monitor.get("summary", {})
    if key == "private_dirty_bytes":
        value = summary.get("private_dirty_net_growth_bytes")
        if isinstance(value, int):
            return value
    if key == "rss_bytes":
        value = summary.get("rss_net_growth_bytes")
        if isinstance(value, int):
            return value
    slopes = summary.get("slopes", {})
    value = nested(slopes, key, "net_growth_bytes")
    if isinstance(value, int):
        return value
    series = monitor.get("series")
    if isinstance(series, list):
        values = [item.get(key) for item in series if isinstance(item, dict) and isinstance(item.get(key), int)]
        if len(values) >= 2:
            return int(values[-1] - values[0])
    return None


def positive_int(value: Any) -> int:
    if isinstance(value, (int, float)) and value > 0:
        return int(value)
    return 0


def object_metrics(object_growth: dict[str, Any]) -> dict[str, Any]:
    rows = object_growth.get("type_growth")
    if not isinstance(rows, list):
        rows = []
    positive_bytes = positive_sum(rows, "bytes_delta")
    top_positive = 0
    top_type = None
    for row in rows:
        value = row.get("bytes_delta")
        if isinstance(value, (int, float)) and value > top_positive:
            top_positive = int(value)
            top_type = row.get("type")
    checkpoint_summary = nested(object_growth, "checkpoint_trend", "summary") or {}
    return {
        "positive_tracked_bytes": positive_bytes,
        "positive_tracked_mib": bytes_to_mib(positive_bytes),
        "top_candidate_type": top_type,
        "top_candidate_bytes": top_positive,
        "top_candidate_mib": bytes_to_mib(top_positive),
        "candidate_coverage_ratio": safe_ratio(top_positive, positive_bytes),
        "checkpoint_verdict": checkpoint_summary.get("verdict"),
        "checkpoint_net_tracked_growth_bytes": checkpoint_summary.get("net_tracked_growth_bytes"),
        "checkpoint_peak_minus_final_bytes": checkpoint_summary.get("peak_minus_final_bytes"),
    }


def tracemalloc_metrics(tracemalloc_payload: dict[str, Any]) -> dict[str, Any]:
    summary = tracemalloc_payload.get("summary", {})
    net = summary.get("net_size_diff_bytes")
    if not isinstance(net, int):
        net = summary.get("top_positive_size_diff_bytes")
    peak_minus_final = summary.get("peak_minus_final_bytes")
    peak = summary.get("peak_traced_bytes")
    current = summary.get("current_traced_bytes")
    return {
        "net_size_diff_bytes": net if isinstance(net, int) else None,
        "net_size_diff_mib": bytes_to_mib(net if isinstance(net, int) else None),
        "peak_traced_bytes": peak if isinstance(peak, int) else None,
        "peak_traced_mib": bytes_to_mib(peak if isinstance(peak, int) else None),
        "current_traced_bytes": current if isinstance(current, int) else None,
        "current_traced_mib": bytes_to_mib(current if isinstance(current, int) else None),
        "peak_minus_final_bytes": peak_minus_final if isinstance(peak_minus_final, int) else None,
        "peak_minus_final_mib": bytes_to_mib(peak_minus_final if isinstance(peak_minus_final, int) else None),
        "verdict": summary.get("verdict"),
    }


def has_retention_evidence(retention: dict[str, Any]) -> bool:
    chains = retention.get("chains")
    summary = retention.get("summary", {})
    return bool(chains) or summary.get("verdict") == "retention_chain_observed"


def has_semantic_evidence(semantic: dict[str, Any]) -> bool:
    summary = semantic.get("summary", {})
    signals = summary.get("dominant_signals") or semantic.get("dominant_signals")
    return bool(signals) or summary.get("verdict") == "semantic_leak_signals_observed"


def semantic_metrics(semantic: dict[str, Any]) -> dict[str, Any]:
    summary = semantic.get("summary", {})
    signals = summary.get("dominant_signals") or semantic.get("dominant_signals") or []
    compact_signals: list[dict[str, Any]] = []
    if isinstance(signals, list):
        for signal in signals[:5]:
            if not isinstance(signal, dict):
                continue
            compact_signals.append(
                {
                    "name": signal.get("name"),
                    "labels": signal.get("labels"),
                    "score": signal.get("score"),
                    "len_delta": signal.get("len_delta"),
                    "currsize_delta": signal.get("currsize_delta"),
                }
            )
    return {
        "verdict": summary.get("verdict"),
        "dominant_signals": compact_signals,
        "competing_signal_count": summary.get("competing_signal_count"),
    }


def retention_metrics(retention: dict[str, Any]) -> dict[str, Any]:
    summary = retention.get("summary", {})
    return {
        "verdict": summary.get("verdict"),
        "root_kind_summary": summary.get("root_kind_summary") if isinstance(summary.get("root_kind_summary"), dict) else {},
    }


def memory_surface_metrics(monitor: dict[str, Any], snapshot: dict[str, Any], rss_delta: int | None) -> dict[str, Any]:
    summary = monitor.get("summary", {})
    slopes = summary.get("slopes", {}) if isinstance(summary.get("slopes"), dict) else {}
    rss_file_net = monitor_net(monitor, "rss_file_bytes")
    rss_shmem_net = monitor_net(monitor, "rss_shmem_bytes")
    file_shmem_net = positive_int(rss_file_net) + positive_int(rss_shmem_net)
    denominator = abs(rss_delta) if isinstance(rss_delta, int) and rss_delta else None
    file_shmem_ratio = safe_ratio(file_shmem_net, denominator)
    shmem_ratio = safe_ratio(positive_int(rss_shmem_net), denominator)

    status = nested(snapshot, "memory_breakdown", "status") or {}
    mapping_summary = snapshot.get("mapping_summary") if isinstance(snapshot.get("mapping_summary"), dict) else {}
    kind_size = mapping_summary.get("kind_size_bytes") if isinstance(mapping_summary.get("kind_size_bytes"), dict) else {}
    kind_counts = mapping_summary.get("kind_counts") if isinstance(mapping_summary.get("kind_counts"), dict) else {}
    rss = status.get("VmRSS_bytes") or 0
    snapshot_file_bytes = positive_int(status.get("RssFile_bytes")) + positive_int(status.get("RssShmem_bytes"))
    mapping_file_bytes = (
        positive_int(kind_size.get("file_backed"))
        + positive_int(kind_size.get("shmem_or_memfd"))
        + positive_int(kind_size.get("deleted_file"))
    )
    mapping_total = sum(positive_int(value) for value in kind_size.values()) if kind_size else 0
    snapshot_ratio = safe_ratio(snapshot_file_bytes, rss)
    mapping_ratio = safe_ratio(mapping_file_bytes, mapping_total)

    growth_ratio_threshold = float(CONFIG["correlation"].get("file_shmem_growth_ratio", 0.6))
    mapping_ratio_threshold = float(CONFIG["correlation"].get("mapping_surface_ratio", 0.5))
    monitor_flags = summary.get("flags") if isinstance(summary.get("flags"), list) else []
    snapshot_flags = nested(snapshot, "readonly_verdict", "flags") or []
    evidence: list[str] = []
    if summary.get("verdict") == "file_or_shmem_growth":
        evidence.append("monitor_verdict:file_or_shmem_growth")
    if "mmap_or_shared_memory_possible" in monitor_flags:
        evidence.append("monitor_flag:mmap_or_shared_memory_possible")
    if "file_or_shmem_dominant_rss" in snapshot_flags:
        evidence.append("snapshot_flag:file_or_shmem_dominant_rss")
    if file_shmem_ratio is not None and file_shmem_ratio >= growth_ratio_threshold:
        evidence.append("monitor_file_shmem_net_growth_dominates")
    if snapshot_ratio is not None and snapshot_ratio >= growth_ratio_threshold:
        evidence.append("snapshot_file_shmem_rss_dominates")
    if mapping_ratio is not None and mapping_ratio >= mapping_ratio_threshold:
        evidence.append("mapping_size_file_shmem_dominates")
    mapping_hints: list[str] = []
    if kind_counts.get("shmem_or_memfd"):
        mapping_hints.append("snapshot_has_shmem_or_memfd_mappings")
    if kind_counts.get("deleted_file"):
        mapping_hints.append("snapshot_has_deleted_file_mappings")

    primary_surface = "unknown"
    if evidence:
        if positive_int(rss_shmem_net) >= positive_int(rss_file_net) and (
            positive_int(rss_shmem_net) or kind_counts.get("shmem_or_memfd")
        ):
            primary_surface = "shmem"
        elif positive_int(rss_file_net) or kind_counts.get("file_backed") or kind_counts.get("deleted_file"):
            primary_surface = "file_backed"
        else:
            primary_surface = "mmap_or_file_backed"

    return {
        "primary_surface": primary_surface,
        "evidence": evidence,
        "hints": mapping_hints,
        "file_shmem_dominant": bool(evidence),
        "rss_file_net_growth_bytes": rss_file_net,
        "rss_file_net_growth_mib": bytes_to_mib(rss_file_net),
        "rss_shmem_net_growth_bytes": rss_shmem_net,
        "rss_shmem_net_growth_mib": bytes_to_mib(rss_shmem_net),
        "file_shmem_net_growth_bytes": file_shmem_net,
        "file_shmem_net_growth_mib": bytes_to_mib(file_shmem_net),
        "file_shmem_growth_ratio": file_shmem_ratio,
        "shmem_growth_ratio": shmem_ratio,
        "snapshot_file_shmem_rss_bytes": snapshot_file_bytes,
        "snapshot_file_shmem_rss_mib": bytes_to_mib(snapshot_file_bytes),
        "snapshot_file_shmem_rss_ratio": snapshot_ratio,
        "mapping_file_shmem_bytes": mapping_file_bytes,
        "mapping_file_shmem_mib": bytes_to_mib(mapping_file_bytes),
        "mapping_file_shmem_ratio": mapping_ratio,
        "thresholds": {
            "file_shmem_growth_ratio": growth_ratio_threshold,
            "mapping_surface_ratio": mapping_ratio_threshold,
        },
        "monitor_slopes": {
            "rss_file_bytes": nested(slopes, "rss_file_bytes", "slope_bytes_per_second"),
            "rss_shmem_bytes": nested(slopes, "rss_shmem_bytes", "slope_bytes_per_second"),
        },
    }


def classify(
    monitor: dict[str, Any],
    snapshot: dict[str, Any],
    object_data: dict[str, Any],
    tracemalloc_data: dict[str, Any],
    semantic: dict[str, Any],
    retention: dict[str, Any],
    missing: list[str],
) -> dict[str, Any]:
    private_delta = monitor_net(monitor, "private_dirty_bytes")
    rss_delta = monitor_net(monitor, "rss_bytes")
    memory_surface = memory_surface_metrics(monitor, snapshot, rss_delta)
    object_info = object_metrics(object_data)
    trace_info = tracemalloc_metrics(tracemalloc_data)
    semantic_info = semantic_metrics(semantic)
    retention_info = retention_metrics(retention)
    denominator = private_delta if private_delta and private_delta > 0 else rss_delta
    python_heap_ratio = safe_ratio(trace_info["net_size_diff_bytes"], denominator)
    tracked_ratio = safe_ratio(object_info["positive_tracked_bytes"], denominator)
    monitor_verdict = nested(monitor, "summary", "verdict")
    monitor_flags = nested(monitor, "summary", "flags") or []
    snapshot_flags = nested(snapshot, "readonly_verdict", "flags") or []
    scope_flags = sorted(set(monitor_flags + snapshot_flags))
    min_peak = int(CONFIG["correlation"]["transient_peak_bytes"])
    confirm_ratio = float(CONFIG["correlation"]["python_heap_ratio_confirm"])
    native_ratio = float(CONFIG["correlation"]["native_heap_ratio_suspect"])
    coverage_ratio = float(CONFIG["correlation"]["candidate_coverage_ratio"])
    heap_evidence = has_semantic_evidence(semantic) or has_retention_evidence(retention)
    object_growth_seen = object_info["positive_tracked_bytes"] > 0 or bool(object_info.get("checkpoint_net_tracked_growth_bytes"))
    trace_growth_seen = (trace_info["net_size_diff_bytes"] or 0) > 0
    monotonic_growth = object_info.get("checkpoint_verdict") == "monotonic_growth"

    reason = "Evidence is insufficient to classify memory root cause."
    confidence_cap = "weak"
    verdict = "readonly_insufficient"
    coverage_warning = None

    peak_minus_final = trace_info["peak_minus_final_bytes"] or object_info["checkpoint_peak_minus_final_bytes"] or 0
    net_trace = trace_info["net_size_diff_bytes"] or 0
    checkpoint_verdict = object_info.get("checkpoint_verdict")
    live_scope_observed = bool(nested(monitor, "summary")) or bool(nested(snapshot, "readonly_verdict"))
    no_live_growth = (
        rss_delta is not None
        and private_delta is not None
        and abs(rss_delta) < min_peak
        and abs(private_delta) < min_peak
    )
    trace_peak_released = trace_info.get("verdict") == "transient_peak_high_but_released"
    peak_released = (peak_minus_final >= min_peak or trace_peak_released) and net_trace < min_peak and (
        checkpoint_verdict != "monotonic_growth" or no_live_growth
    )
    if monitor_verdict in {"cgroup_growth_not_target", "worker_skew_growth"}:
        verdict = "readonly_insufficient"
        reason = "Observed memory growth is outside the selected target PID scope."
        confidence_cap = "weak_scope_mismatch"
    elif monitor_verdict == "plateau_high_water":
        verdict = "allocator_reuse_or_fragmentation_possible"
        reason = "RSS reached a high-water plateau without sustained final retained growth evidence."
        confidence_cap = "direction_only_without_longer_window"
    elif peak_released and live_scope_observed and not has_semantic_evidence(semantic):
        verdict = "allocator_reuse_or_fragmentation_possible"
        reason = "Live PID evidence is stable after a material peak and no semantic retained Python owner was found."
        confidence_cap = "direction_only_without_longer_window"
    elif peak_released:
        verdict = "transient_peak_not_retained"
        reason = "Peak memory is materially higher than final retained memory."
        confidence_cap = "medium_without_fix_retest"
    elif memory_surface["file_shmem_dominant"]:
        verdict = "mmap_or_file_backed_growth"
        reason = "RSS growth or snapshot is dominated by file/shmem-backed mappings before Python heap or native allocator attribution."
        confidence_cap = "medium_mapping_evidence"
    elif (
        (python_heap_ratio is not None and python_heap_ratio >= confirm_ratio)
        or (tracked_ratio is not None and tracked_ratio >= confirm_ratio)
    ) and heap_evidence:
        verdict = "python_retained_leak_likely"
        reason = "Python heap evidence explains the dominant private/RSS growth and retention/semantic evidence exists."
        confidence_cap = "medium_static_retention"
    elif denominator is None and heap_evidence and (monotonic_growth or object_growth_seen or trace_growth_seen):
        verdict = "python_retained_leak_likely"
        reason = "Reproducible workload shows Python object/allocation growth with semantic or retention evidence, but no process RSS denominator was provided."
        confidence_cap = "medium_workload_only_without_live_rss_scope"
    elif denominator and denominator > 0 and not heap_evidence and not (trace_growth_seen or object_growth_seen):
        verdict = "readonly_insufficient"
        reason = "External RSS growth was observed, but no Python heap, semantic, or retention evidence was provided."
        confidence_cap = "weak_without_reproducible_heap_evidence"
    elif denominator and denominator > 0 and (
        (python_heap_ratio is not None and python_heap_ratio <= native_ratio)
        and (tracked_ratio is None or tracked_ratio <= native_ratio)
    ):
        verdict = "native_or_allocator_suspect"
        reason = "Private/RSS growth is not explained by Python traced heap or tracked objects."
        confidence_cap = "direction_only_without_native_allocator_stack"
    elif denominator and denominator > 0 and (python_heap_ratio is not None or tracked_ratio is not None):
        verdict = "mixed_growth"
        reason = "Python heap explains part, but not all, of observed process memory growth."
        confidence_cap = "medium_mixed_evidence"

    dominant_signals = semantic_info.get("dominant_signals") or []
    competing_count = semantic_info.get("competing_signal_count") or 0
    has_competing_semantics = bool(competing_count) or len(dominant_signals) > 1
    if (
        verdict in {"python_retained_leak_likely", "mixed_growth"}
        and has_competing_semantics
        and object_info["candidate_coverage_ratio"] is not None
        and object_info["candidate_coverage_ratio"] < coverage_ratio
    ):
        coverage_warning = "top_candidate_low_coverage_check_competing_semantic_and_retention_signals"

    return {
        "verdict": verdict,
        "reason": reason,
        "confidence_cap": confidence_cap,
        "missing_evidence": missing,
        "scope_flags": scope_flags,
        "monitor_verdict": monitor_verdict,
        "private_dirty_net_growth_bytes": private_delta,
        "private_dirty_net_growth_mib": bytes_to_mib(private_delta),
        "rss_net_growth_bytes": rss_delta,
        "rss_net_growth_mib": bytes_to_mib(rss_delta),
        "python_heap_to_private_dirty_ratio": python_heap_ratio,
        "tracked_object_to_private_dirty_ratio": tracked_ratio,
        "memory_surface": memory_surface,
        "tracemalloc_peak_vs_final": {
            "peak_traced_bytes": trace_info["peak_traced_bytes"],
            "current_traced_bytes": trace_info["current_traced_bytes"],
            "peak_minus_final_bytes": trace_info["peak_minus_final_bytes"],
            "verdict": trace_info["verdict"],
        },
        "candidate_coverage_ratio": object_info["candidate_coverage_ratio"],
        "coverage_warning": coverage_warning,
        "object_growth": object_info,
        "tracemalloc": trace_info,
        "semantic": semantic_info,
        "retention": retention_info,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Correlate memory leak evidence and produce a final confidence gate.")
    parser.add_argument("--monitor", help="monitor_rss.py JSON output.")
    parser.add_argument("--snapshot", help="live_process_snapshot.py JSON output.")
    parser.add_argument("--object-growth", help="object_growth.py JSON output.")
    parser.add_argument("--tracemalloc", help="tracemalloc_probe.py JSON output.")
    parser.add_argument("--semantic", help="semantic_probe.py JSON output.")
    parser.add_argument("--retention", help="retention_chain.py JSON output.")
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    try:
        monitor_payload, missing_monitor = load_payload(args.monitor, "monitor")
        snapshot_payload, missing_snapshot = load_payload(args.snapshot, "snapshot")
        object_payload, missing_object = load_payload(args.object_growth, "object_growth")
        trace_payload, missing_trace = load_payload(args.tracemalloc, "tracemalloc")
        semantic_payload, missing_semantic = load_payload(args.semantic, "semantic")
        retention_payload, missing_retention = load_payload(args.retention, "retention")
    except (OSError, json.JSONDecodeError) as exc:
        print_json(error_payload("input", str(exc)), args.output)
        return 2

    missing = [
        item
        for item in [missing_monitor, missing_snapshot, missing_object, missing_trace, missing_semantic, missing_retention]
        if item
    ]
    monitor = results(monitor_payload)
    snapshot = results(snapshot_payload)
    object_data = results(object_payload)
    trace_data = results(trace_payload)
    semantic = results(semantic_payload)
    retention = results(retention_payload)
    summary = classify(monitor, snapshot, object_data, trace_data, semantic, retention, missing)
    payload = result(
        "success" if len(missing) < 6 else "partial",
        {
            "summary": summary,
            "evidence_inputs": {
                "monitor": os.path.abspath(args.monitor) if args.monitor else None,
                "snapshot": os.path.abspath(args.snapshot) if args.snapshot else None,
                "object_growth": os.path.abspath(args.object_growth) if args.object_growth else None,
                "tracemalloc": os.path.abspath(args.tracemalloc) if args.tracemalloc else None,
                "semantic": os.path.abspath(args.semantic) if args.semantic else None,
                "retention": os.path.abspath(args.retention) if args.retention else None,
            },
        },
        backend_used="stdlib:evidence-correlation",
        degraded_capabilities=["Correlation is a confidence gate; it does not collect new heap or native stacks."],
        next_steps=[
            "Final report must cite correlation verdict and confidence_cap before claiming root cause.",
            "Final report must list missing_evidence and keep read-only or native conclusions within confidence_cap.",
            "If verdict=mmap_or_file_backed_growth, describe the file/shmem/mmap memory surface before any Python heap or native allocator attribution.",
            "If verdict=native_or_allocator_suspect, keep conclusion direction-level without native allocator stack evidence.",
            "If verdict=readonly_insufficient, request reproducible workload, heap snapshot, or broader process/cgroup scope.",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
