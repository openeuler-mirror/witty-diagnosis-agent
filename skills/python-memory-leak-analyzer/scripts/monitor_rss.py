#!/usr/bin/env python3
"""External RSS/VMS/cgroup sampler for Python leak triage."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from collections import Counter
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, print_json, result


STATUS_KB_FIELDS = {
    "VmRSS",
    "VmSize",
    "VmHWM",
    "VmData",
    "VmSwap",
    "RssAnon",
    "RssFile",
    "RssShmem",
}


def read_text(path: str, limit: int | None = None) -> str | None:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return handle.read(limit)
    except OSError:
        return None


def read_status(pid: int) -> dict[str, int]:
    metrics: dict[str, int] = {}
    data = read_text(f"/proc/{pid}/status")
    if data is None:
        return metrics
    for line in data.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        parts = raw.split()
        if key in STATUS_KB_FIELDS and parts and parts[0].isdigit():
            metrics[key] = int(parts[0]) * 1024
        elif key in {"Threads", "FDSize"} and parts and parts[0].isdigit():
            metrics[key] = int(parts[0])
    return metrics


def read_smaps_rollup(pid: int) -> dict[str, int]:
    path = f"/proc/{pid}/smaps_rollup"
    fields = {"Rss", "Pss", "Private_Clean", "Private_Dirty", "Shared_Clean", "Shared_Dirty", "Anonymous", "Swap"}
    data = read_text(path)
    rows: dict[str, int] = {}
    if data is None:
        return rows
    for line in data.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        parts = raw.split()
        if key in fields and parts and parts[0].isdigit():
            rows[key] = int(parts[0]) * 1024
    return rows


def safe_cgroup_path(base: str, relative: str) -> str | None:
    candidate = os.path.abspath(os.path.join(base, relative.lstrip("/")))
    base_abs = os.path.abspath(base)
    if candidate == base_abs or candidate.startswith(base_abs + os.sep):
        return candidate
    return None


def read_int_file(path: str) -> int | None:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            raw = handle.read().strip()
        if raw == "max":
            return None
        return int(raw)
    except (OSError, ValueError):
        return None


def read_pid_cgroup_memory_current(pid: int) -> int | None:
    data = read_text(f"/proc/{pid}/cgroup")
    if data is None:
        return None
    for line in data.splitlines():
        parts = line.split(":", 2)
        if len(parts) != 3:
            continue
        hierarchy, controllers, cg_path = parts
        controller_set = set(filter(None, controllers.split(",")))
        if hierarchy == "0" and controllers == "":
            fs_path = safe_cgroup_path("/sys/fs/cgroup", cg_path)
            if fs_path:
                value = read_int_file(os.path.join(fs_path, "memory.current"))
                if value is not None:
                    return value
        if "memory" in controller_set:
            fs_path = safe_cgroup_path("/sys/fs/cgroup/memory", cg_path)
            if fs_path:
                value = read_int_file(os.path.join(fs_path, "memory.usage_in_bytes"))
                if value is not None:
                    return value
    return None


def direct_children(pid: int) -> list[int]:
    children: set[int] = set()
    task_dir = f"/proc/{pid}/task"
    try:
        tids = os.listdir(task_dir)
    except OSError:
        tids = []
    for tid in tids:
        data = read_text(os.path.join(task_dir, tid, "children"))
        if not data:
            continue
        for raw in data.split():
            if raw.isdigit():
                children.add(int(raw))
    return sorted(children)


def child_memory(pid: int) -> dict[str, Any]:
    rows = []
    for child in direct_children(pid):
        if not os.path.isdir(f"/proc/{child}"):
            continue
        status = read_status(child)
        smaps = read_smaps_rollup(child)
        rows.append(
            {
                "pid": child,
                "rss_bytes": status.get("VmRSS"),
                "private_dirty_bytes": smaps.get("Private_Dirty"),
            }
        )
    total_rss = sum(item.get("rss_bytes") or 0 for item in rows)
    total_private_dirty = sum(item.get("private_dirty_bytes") or 0 for item in rows)
    rows.sort(key=lambda item: item.get("rss_bytes") or 0, reverse=True)
    return {
        "child_count": len(rows),
        "children_rss_bytes": total_rss,
        "children_private_dirty_bytes": total_private_dirty,
        "largest_child_pid": rows[0]["pid"] if rows else None,
        "largest_child_rss_bytes": rows[0].get("rss_bytes") if rows else None,
    }


def mapping_counts(pid: int) -> dict[str, Any]:
    data = read_text(f"/proc/{pid}/maps")
    counts: Counter[str] = Counter()
    if data is None:
        return {"maps_available": False}
    for line in data.splitlines():
        parts = line.split(maxsplit=5)
        pathname = parts[5] if len(parts) > 5 else ""
        lowered = pathname.lower()
        if not pathname:
            counts["anonymous"] += 1
        elif pathname == "[heap]":
            counts["heap"] += 1
        elif pathname.startswith("[stack"):
            counts["stack"] += 1
        elif "memfd:" in lowered or "/dev/shm" in lowered or "shm" in lowered:
            counts["shmem_or_memfd"] += 1
        elif "deleted" in lowered:
            counts["deleted_file"] += 1
        elif pathname.startswith("["):
            counts["special"] += 1
        elif ".so" in lowered:
            counts["shared_library"] += 1
        else:
            counts["file_backed"] += 1
    return {"maps_available": True, "mapping_counts": dict(counts)}


def sample(pid: int, started_at: float) -> dict[str, Any]:
    status = read_status(pid)
    smaps = read_smaps_rollup(pid)
    children = child_memory(pid)
    row = {
        "t": round(time.time() - started_at, 3),
        "rss_bytes": status.get("VmRSS"),
        "vms_bytes": status.get("VmSize"),
        "hwm_bytes": status.get("VmHWM"),
        "rss_anon_bytes": status.get("RssAnon"),
        "rss_file_bytes": status.get("RssFile"),
        "rss_shmem_bytes": status.get("RssShmem"),
        "vmdata_bytes": status.get("VmData"),
        "vmswap_bytes": status.get("VmSwap"),
        "private_dirty_bytes": smaps.get("Private_Dirty"),
        "private_clean_bytes": smaps.get("Private_Clean"),
        "shared_clean_bytes": smaps.get("Shared_Clean"),
        "shared_dirty_bytes": smaps.get("Shared_Dirty"),
        "anonymous_bytes": smaps.get("Anonymous"),
        "pss_bytes": smaps.get("Pss"),
        "cgroup_memory_current_bytes": read_pid_cgroup_memory_current(pid),
        **children,
    }
    row.update(mapping_counts(pid))
    return row


def slope(points: list[dict[str, Any]], key: str) -> float | None:
    values = [(p["t"], p.get(key)) for p in points if isinstance(p.get(key), int)]
    if len(values) < 2:
        return None
    n = len(values)
    mean_x = sum(x for x, _ in values) / n
    mean_y = sum(y for _, y in values) / n
    denom = sum((x - mean_x) ** 2 for x, _ in values)
    if denom == 0:
        return 0.0
    return sum((x - mean_x) * (y - mean_y) for x, y in values) / denom


def net_delta(series: list[dict[str, Any]], key: str) -> int | None:
    values = [p.get(key) for p in series if isinstance(p.get(key), int)]
    if len(values) < 2:
        return None
    return int(values[-1] - values[0])


def slope_summary(series: list[dict[str, Any]]) -> dict[str, Any]:
    keys = [
        "rss_bytes",
        "private_dirty_bytes",
        "rss_anon_bytes",
        "rss_file_bytes",
        "rss_shmem_bytes",
        "cgroup_memory_current_bytes",
        "children_rss_bytes",
        "children_private_dirty_bytes",
    ]
    return {
        key: {
            "slope_bytes_per_second": round(value, 3) if (value := slope(series, key)) is not None else None,
            "net_growth_bytes": net_delta(series, key),
            "net_growth_mib": bytes_to_mib(net_delta(series, key)),
        }
        for key in keys
    }


def classify(series: list[dict[str, Any]], config: dict[str, Any]) -> dict[str, Any]:
    min_samples = int(config["monitor"]["min_samples"])
    slopes = slope_summary(series)
    rss_slope = slopes["rss_bytes"]["slope_bytes_per_second"]
    rss_net = slopes["rss_bytes"]["net_growth_bytes"]
    threshold = int(config["monitor"]["rss_growth_bytes_per_second"])
    if len(series) < min_samples or rss_slope is None:
        return {
            "verdict": "insufficient_window",
            "growth_shape": "insufficient_samples",
            "slopes": slopes,
            "reason": "sampling window is too short",
        }

    private_dirty_slope = slopes["private_dirty_bytes"]["slope_bytes_per_second"] or 0
    cgroup_slope = slopes["cgroup_memory_current_bytes"]["slope_bytes_per_second"] or 0
    child_slope = slopes["children_rss_bytes"]["slope_bytes_per_second"] or 0
    file_slope = (slopes["rss_file_bytes"]["slope_bytes_per_second"] or 0) + (
        slopes["rss_shmem_bytes"]["slope_bytes_per_second"] or 0
    )
    rss_values = [p["rss_bytes"] for p in series if isinstance(p.get("rss_bytes"), int)]
    total_delta = max(rss_values) - min(rss_values) if rss_values else 0
    tail = rss_values[max(0, len(rss_values) * 2 // 3) :]
    tail_delta = max(tail) - min(tail) if tail else 0
    plateau_tail_ratio = float(config["monitor"]["plateau_tail_ratio"])
    flags: list[str] = []

    if cgroup_slope > threshold and rss_slope < threshold:
        verdict = "cgroup_growth_not_target"
        shape = "cgroup_growth_target_pid_flat"
        flags.append("target_pid_does_not_explain_cgroup_growth")
    elif child_slope > threshold and child_slope > max(rss_slope, 0) * 1.5:
        verdict = "worker_skew_growth"
        shape = "child_process_growth_dominates"
        flags.append("expand_scope_to_process_tree")
    elif file_slope > threshold and file_slope > max(private_dirty_slope, 0):
        verdict = "file_or_shmem_growth"
        shape = "file_or_shmem_backed_rss_growth"
        flags.append("mmap_or_shared_memory_possible")
    elif rss_slope > threshold and (rss_net or 0) > threshold:
        verdict = "target_pid_growth"
        shape = "linear_or_step_growth"
        if private_dirty_slope <= 0:
            flags.append("rss_growth_without_private_dirty_growth")
    elif total_delta > 0 and tail_delta <= max(1024 * 1024, total_delta * plateau_tail_ratio):
        verdict = "plateau_high_water"
        shape = "plateau"
        flags.append("high_water_or_cache_warmup_possible")
    else:
        verdict = "insufficient_window"
        shape = "noise_or_workload_coupled"

    return {
        "verdict": verdict,
        "growth_shape": shape,
        "flags": flags,
        "slopes": slopes,
        "rss_slope_bytes_per_second": rss_slope,
        "private_dirty_slope_bytes_per_second": private_dirty_slope,
        "rss_net_growth_bytes": rss_net,
        "rss_net_growth_mib": bytes_to_mib(rss_net),
        "private_dirty_net_growth_bytes": slopes["private_dirty_bytes"]["net_growth_bytes"],
        "private_dirty_net_growth_mib": slopes["private_dirty_bytes"]["net_growth_mib"],
        "interpretation": "Time-series trend only defines memory surface; Python root cause requires heap and retention evidence.",
    }


def launch_command(command: str) -> subprocess.Popen:
    return subprocess.Popen(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sample RSS/VMS/Private_Dirty/cgroup metrics for a PID or command.")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--pid", type=int, help="Existing process PID. This is read-only external observation.")
    group.add_argument("--cmd", help="Command to start and monitor from process birth.")
    parser.add_argument("--interval", type=float, default=CONFIG["monitor"]["interval_seconds"])
    parser.add_argument("--duration", type=float, default=CONFIG["monitor"]["duration_seconds"])
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    if not os.path.isdir("/proc"):
        print_json(error_payload("unavailable", "/proc is required for monitor_rss.py"), args.output)
        return 4

    proc = None
    pid = args.pid
    stdout_tail = ""
    stderr_tail = ""
    if args.cmd:
        proc = launch_command(args.cmd)
        pid = proc.pid
    if pid is None or not os.path.isdir(f"/proc/{pid}"):
        print_json(error_payload("input", f"PID {pid} does not exist"), args.output)
        return 2

    started = time.time()
    series: list[dict[str, Any]] = []
    end_at = started + max(args.duration, args.interval)
    try:
        while time.time() <= end_at:
            if not os.path.isdir(f"/proc/{pid}"):
                break
            series.append(sample(pid, started))
            time.sleep(max(0.1, args.interval))
    finally:
        if proc and proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
        if proc:
            out, err = proc.communicate(timeout=1)
            stdout_tail = out[-2000:] if out else ""
            stderr_tail = err[-2000:] if err else ""

    analysis = classify(series, CONFIG)
    next_steps = [
        "先用 live_process_snapshot.py 复核 PID、cgroup、mapping 和子进程范围。",
        "若 verdict=target_pid_growth，继续运行 object_growth.py/tracemalloc_probe.py 归因 Python 堆。",
        "若 verdict=cgroup_growth_not_target 或 worker_skew_growth，扩大到 cgroup 或 worker PID 后再下结论。",
        "若 verdict=file_or_shmem_growth，优先排查 mmap/file/shmem，不要直接确认 Python 对象泄漏。",
    ]
    payload = result(
        "success" if series else "partial",
        {
            "pid": pid,
            "command": args.cmd,
            "summary": analysis,
            "series": series,
            "process_output_tail": {"stdout": stdout_tail, "stderr": stderr_tail},
        },
        backend_used="stdlib:/proc",
        degraded_capabilities=["No Python heap attribution in monitor_rss.py; use in-process scripts for root cause."],
        next_steps=next_steps,
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
