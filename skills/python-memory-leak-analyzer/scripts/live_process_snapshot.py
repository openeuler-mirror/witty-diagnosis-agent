#!/usr/bin/env python3
"""Read-only live PID scope and memory snapshot for production triage."""

from __future__ import annotations

import argparse
import os
import sys
from collections import Counter
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import CONFIG, bytes_to_mib, error_payload, print_json, result


KB_FIELDS = {
    "VmPeak",
    "VmSize",
    "VmLck",
    "VmPin",
    "VmHWM",
    "VmRSS",
    "RssAnon",
    "RssFile",
    "RssShmem",
    "VmData",
    "VmStk",
    "VmExe",
    "VmLib",
    "VmPTE",
    "VmSwap",
}

SMAPS_FIELDS = {
    "Rss",
    "Pss",
    "Shared_Clean",
    "Shared_Dirty",
    "Private_Clean",
    "Private_Dirty",
    "Referenced",
    "Anonymous",
    "LazyFree",
    "AnonHugePages",
    "ShmemPmdMapped",
    "FilePmdMapped",
    "Shared_Hugetlb",
    "Private_Hugetlb",
    "Swap",
    "SwapPss",
}


def read_text(path: str, limit: int | None = None) -> str | None:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            data = handle.read(limit)
            return data
    except OSError:
        return None


def read_status(pid: int) -> dict[str, Any]:
    path = f"/proc/{pid}/status"
    data = read_text(path)
    if data is None:
        raise FileNotFoundError(path)
    rows: dict[str, Any] = {}
    for line in data.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        parts = raw.split()
        if not parts:
            rows[key] = ""
            continue
        if key in KB_FIELDS and parts[0].isdigit():
            rows[f"{key}_bytes"] = int(parts[0]) * 1024
            rows[f"{key}_mib"] = bytes_to_mib(int(parts[0]) * 1024)
        elif key in {"Pid", "PPid", "Threads", "FDSize"} and parts[0].isdigit():
            rows[key] = int(parts[0])
        else:
            rows[key] = raw.strip()
    return rows


def read_cmdline(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as handle:
            content = handle.read(8192).replace(b"\x00", b" ").strip()
            return content.decode("utf-8", errors="replace")
    except OSError:
        return ""


def read_link(path: str) -> str | None:
    try:
        return os.readlink(path)
    except OSError:
        return None


def count_fds(pid: int) -> int | None:
    try:
        return len(os.listdir(f"/proc/{pid}/fd"))
    except OSError:
        return None


def parse_kb_file(path: str, fields: set[str]) -> dict[str, Any]:
    data = read_text(path)
    if data is None:
        return {"available": False}
    rows: dict[str, Any] = {"available": True}
    for line in data.splitlines():
        if ":" not in line:
            continue
        key, raw = line.split(":", 1)
        if key not in fields:
            continue
        parts = raw.split()
        if parts and parts[0].isdigit():
            value = int(parts[0]) * 1024
            rows[f"{key}_bytes"] = value
            rows[f"{key}_mib"] = bytes_to_mib(value)
    return rows


def mapping_kind(pathname: str) -> str:
    if not pathname:
        return "anonymous"
    lowered = pathname.lower()
    if pathname == "[heap]":
        return "heap"
    if pathname.startswith("[stack"):
        return "stack"
    if "deleted" in lowered:
        return "deleted_file"
    if pathname.startswith("["):
        return "special"
    if "memfd:" in lowered or "/dev/shm" in lowered or "shm" in lowered:
        return "shmem_or_memfd"
    if ".so" in lowered:
        return "shared_library"
    return "file_backed"


def parse_maps(pid: int) -> dict[str, Any]:
    path = f"/proc/{pid}/maps"
    data = read_text(path)
    if data is None:
        return {"available": False, "permission_limited": True}
    totals: Counter[str] = Counter()
    counts: Counter[str] = Counter()
    largest: list[dict[str, Any]] = []
    for line in data.splitlines():
        parts = line.split(maxsplit=5)
        if len(parts) < 5 or "-" not in parts[0]:
            continue
        start_raw, end_raw = parts[0].split("-", 1)
        try:
            size = int(end_raw, 16) - int(start_raw, 16)
        except ValueError:
            continue
        pathname = parts[5] if len(parts) > 5 else ""
        kind = mapping_kind(pathname)
        totals[kind] += size
        counts[kind] += 1
        largest.append(
            {
                "address_range": parts[0],
                "perms": parts[1],
                "kind": kind,
                "size_bytes": size,
                "size_mib": bytes_to_mib(size),
                "pathname": pathname,
            }
        )
    largest.sort(key=lambda item: item["size_bytes"], reverse=True)
    return {
        "available": True,
        "total_vma": sum(counts.values()),
        "kind_counts": dict(counts),
        "kind_size_bytes": dict(totals),
        "kind_size_mib": {key: bytes_to_mib(value) for key, value in totals.items()},
        "largest_mappings": largest[: int(CONFIG["live_process"]["top_mappings"])],
    }


def parse_smaps_detail(pid: int, top: int) -> dict[str, Any]:
    path = f"/proc/{pid}/smaps"
    data = read_text(path)
    if data is None:
        return {"available": False, "permission_limited": True}
    rows: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None

    def flush() -> None:
        if current:
            rows.append(current)

    for line in data.splitlines():
        if "-" in line.split(maxsplit=1)[0] and len(line.split()) >= 5:
            flush()
            parts = line.split(maxsplit=5)
            pathname = parts[5] if len(parts) > 5 else ""
            start_raw, end_raw = parts[0].split("-", 1)
            try:
                size = int(end_raw, 16) - int(start_raw, 16)
            except ValueError:
                size = 0
            current = {
                "address_range": parts[0],
                "perms": parts[1],
                "kind": mapping_kind(pathname),
                "size_bytes": size,
                "size_mib": bytes_to_mib(size),
                "pathname": pathname,
            }
            continue
        if current and ":" in line:
            key, raw = line.split(":", 1)
            if key in SMAPS_FIELDS:
                parts = raw.split()
                if parts and parts[0].isdigit():
                    value = int(parts[0]) * 1024
                    current[f"{key}_bytes"] = value
                    current[f"{key}_mib"] = bytes_to_mib(value)
    flush()
    rows.sort(key=lambda item: item.get("Rss_bytes", 0), reverse=True)
    return {"available": True, "top_mappings_by_rss": rows[:top]}


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


def read_key_value_file(path: str) -> dict[str, int]:
    data = read_text(path)
    rows: dict[str, int] = {}
    if data is None:
        return rows
    for line in data.splitlines():
        parts = line.split()
        if len(parts) == 2:
            try:
                rows[parts[0]] = int(parts[1])
            except ValueError:
                continue
    return rows


def read_cgroup_scope(pid: int) -> dict[str, Any]:
    data = read_text(f"/proc/{pid}/cgroup")
    if data is None:
        return {"available": False}
    entries = []
    memory_current = None
    memory_max = None
    events: dict[str, int] = {}
    for line in data.splitlines():
        parts = line.split(":", 2)
        if len(parts) != 3:
            continue
        hierarchy, controllers, cg_path = parts
        controller_set = set(filter(None, controllers.split(",")))
        entry: dict[str, Any] = {
            "hierarchy": hierarchy,
            "controllers": sorted(controller_set),
            "path": cg_path,
        }
        if hierarchy == "0" and controllers == "":
            fs_path = safe_cgroup_path("/sys/fs/cgroup", cg_path)
            entry["fs_path"] = fs_path
            if fs_path:
                current = read_int_file(os.path.join(fs_path, "memory.current"))
                limit = read_int_file(os.path.join(fs_path, "memory.max"))
                if current is not None:
                    memory_current = current
                if limit is not None:
                    memory_max = limit
                events.update(read_key_value_file(os.path.join(fs_path, "memory.events")))
        elif "memory" in controller_set:
            fs_path = safe_cgroup_path("/sys/fs/cgroup/memory", cg_path)
            entry["fs_path"] = fs_path
            if fs_path:
                current = read_int_file(os.path.join(fs_path, "memory.usage_in_bytes"))
                limit = read_int_file(os.path.join(fs_path, "memory.limit_in_bytes"))
                if current is not None:
                    memory_current = current
                if limit is not None:
                    memory_max = limit
                failcnt = read_int_file(os.path.join(fs_path, "memory.failcnt"))
                if failcnt is not None:
                    events["failcnt"] = failcnt
        entries.append(entry)
    return {
        "available": True,
        "entries": entries,
        "memory_current_bytes": memory_current,
        "memory_current_mib": bytes_to_mib(memory_current),
        "memory_max_bytes": memory_max,
        "memory_max_mib": bytes_to_mib(memory_max),
        "memory_events": events,
    }


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
    if children:
        return sorted(children)
    try:
        proc_entries = [name for name in os.listdir("/proc") if name.isdigit()]
    except OSError:
        return []
    for raw_pid in proc_entries:
        child_pid = int(raw_pid)
        try:
            status = read_status(child_pid)
        except OSError:
            continue
        if status.get("PPid") == pid:
            children.add(child_pid)
    return sorted(children)


def summarize_children(pid: int) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    for child in direct_children(pid):
        try:
            status = read_status(child)
        except OSError:
            continue
        smaps = parse_kb_file(f"/proc/{child}/smaps_rollup", {"Private_Dirty", "Rss"})
        row = {
            "pid": child,
            "name": status.get("Name", ""),
            "cmdline": read_cmdline(child)[:300],
            "rss_bytes": status.get("VmRSS_bytes"),
            "rss_mib": status.get("VmRSS_mib"),
            "private_dirty_bytes": smaps.get("Private_Dirty_bytes"),
            "private_dirty_mib": smaps.get("Private_Dirty_mib"),
        }
        rows.append(row)
    total_rss = sum(item.get("rss_bytes") or 0 for item in rows)
    total_private_dirty = sum(item.get("private_dirty_bytes") or 0 for item in rows)
    rows.sort(key=lambda item: item.get("rss_bytes") or 0, reverse=True)
    return {
        "child_count": len(rows),
        "total_child_rss_bytes": total_rss,
        "total_child_rss_mib": bytes_to_mib(total_rss),
        "total_child_private_dirty_bytes": total_private_dirty,
        "total_child_private_dirty_mib": bytes_to_mib(total_private_dirty),
        "largest_children": rows[:10],
    }


def readonly_verdict(status: dict[str, Any], smaps: dict[str, Any], maps: dict[str, Any], children: dict[str, Any]) -> dict[str, Any]:
    rss = status.get("VmRSS_bytes") or 0
    rss_file = status.get("RssFile_bytes") or 0
    rss_shmem = status.get("RssShmem_bytes") or 0
    private_dirty = smaps.get("Private_Dirty_bytes") or 0
    child_rss = children.get("total_child_rss_bytes") or 0
    flags: list[str] = []
    verdict = "live_pid_scope_collected"
    confidence_cap = "readonly_scope_only"

    if children.get("child_count", 0) > 0:
        flags.append("process_tree_present")
    if child_rss and rss and child_rss > rss:
        flags.append("children_memory_exceeds_target_pid")
        verdict = "process_tree_scope_required"
    if rss and (rss_file + rss_shmem) > max(private_dirty, rss * 0.5):
        flags.append("file_or_shmem_dominant_rss")
        verdict = "file_or_shmem_mapping_possible"
    if maps.get("kind_counts", {}).get("deleted_file"):
        flags.append("deleted_file_mapping_present")
    if not smaps.get("available"):
        flags.append("smaps_rollup_unavailable")
        confidence_cap = "rss_only"

    return {
        "verdict": verdict,
        "confidence_cap": confidence_cap,
        "flags": flags,
        "reason": "Read-only snapshot defines scope and memory surfaces; growth and Python root cause require time series and heap evidence.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only /proc snapshot for a live Python memory triage PID.")
    parser.add_argument("--pid", type=int, required=True, help="Target process PID. No attach, ptrace, or mutation is performed.")
    parser.add_argument("--detail-smaps", action="store_true", help="Read full /proc/<pid>/smaps and report top mappings by RSS.")
    parser.add_argument("--top", type=int, default=CONFIG["live_process"]["top_mappings"], help="Top mappings to keep for --detail-smaps.")
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    if not os.path.isdir("/proc"):
        print_json(error_payload("unavailable", "/proc is required for live_process_snapshot.py"), args.output)
        return 4
    if not os.path.isdir(f"/proc/{args.pid}"):
        print_json(error_payload("input", f"PID {args.pid} does not exist"), args.output)
        return 2
    try:
        status = read_status(args.pid)
    except OSError as exc:
        print_json(error_payload("permission", str(exc), details={"pid": args.pid}), args.output)
        return 3

    smaps = parse_kb_file(f"/proc/{args.pid}/smaps_rollup", SMAPS_FIELDS)
    maps = parse_maps(args.pid)
    cgroup = read_cgroup_scope(args.pid)
    children = summarize_children(args.pid)
    detail = parse_smaps_detail(args.pid, args.top) if args.detail_smaps else {"available": False, "reason": "not_requested"}
    process_scope = {
        "pid": args.pid,
        "ppid": status.get("PPid"),
        "name": status.get("Name", ""),
        "state": status.get("State", ""),
        "threads": status.get("Threads"),
        "fd_size": status.get("FDSize"),
        "fd_count": count_fds(args.pid),
        "cmdline": read_cmdline(args.pid),
        "exe": read_link(f"/proc/{args.pid}/exe"),
        "cwd": read_link(f"/proc/{args.pid}/cwd"),
    }
    memory = {
        "status": {key: value for key, value in status.items() if key.endswith("_bytes") or key.endswith("_mib")},
        "smaps_rollup": smaps,
    }
    summary = readonly_verdict(status, smaps, maps, children)
    payload = result(
        "success",
        {
            "process_scope": process_scope,
            "memory_breakdown": memory,
            "mapping_summary": maps,
            "smaps_detail": detail,
            "cgroup_scope": cgroup,
            "children_summary": children,
            "summary": summary,
            "readonly_verdict": summary,
        },
        backend_used="stdlib:/proc",
        degraded_capabilities=["Read-only snapshot cannot confirm Python object retention without heap evidence."],
        next_steps=[
            "Run monitor_rss.py --pid for time-series growth shape.",
            "If target PID is stable but child or cgroup memory grows, expand scope to process tree or cgroup.",
            "If file/shmem mappings dominate, treat RSS growth as mmap/file-backed until Python heap evidence proves otherwise.",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
