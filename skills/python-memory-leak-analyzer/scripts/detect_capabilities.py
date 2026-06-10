#!/usr/bin/env python3
"""Detect lightweight runtime boundaries for Python memory leak analysis."""

from __future__ import annotations

import argparse
import os
import platform
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import print_json, result


def read_file(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def detect_proc() -> dict:
    proc_available = os.path.isdir("/proc")
    ptrace_scope = read_file("/proc/sys/kernel/yama/ptrace_scope") if proc_available else None
    smaps_rollup_path = "/proc/self/smaps_rollup"
    return {
        "proc_available": proc_available,
        "smaps_rollup_available": proc_available and os.path.exists(smaps_rollup_path),
        "smaps_rollup_path": smaps_rollup_path if proc_available and os.path.exists(smaps_rollup_path) else None,
        "ptrace_scope": ptrace_scope,
        "ptrace_default_ok": proc_available and ptrace_scope in {None, "0"},
    }


def detect_cgroup() -> dict:
    if os.path.exists("/sys/fs/cgroup/cgroup.controllers"):
        return {
            "version": "v2",
            "memory_current": os.path.exists("/sys/fs/cgroup/memory.current"),
            "memory_current_path": "/sys/fs/cgroup/memory.current",
            "memory_max": os.path.exists("/sys/fs/cgroup/memory.max"),
            "memory_max_path": "/sys/fs/cgroup/memory.max",
        }
    if os.path.isdir("/sys/fs/cgroup/memory"):
        return {
            "version": "v1",
            "memory_current": os.path.exists("/sys/fs/cgroup/memory/memory.usage_in_bytes"),
            "memory_current_path": "/sys/fs/cgroup/memory/memory.usage_in_bytes",
            "memory_max": os.path.exists("/sys/fs/cgroup/memory/memory.limit_in_bytes"),
            "memory_max_path": "/sys/fs/cgroup/memory/memory.limit_in_bytes",
        }
    return {
        "version": "none",
        "memory_current": False,
        "memory_current_path": None,
        "memory_max": False,
        "memory_max_path": None,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect runtime boundaries for python-memory-leak-analyzer.")
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    proc = detect_proc()
    cgroup = detect_cgroup()
    recommended_path = (
        "可重启/可复现时使用 --script 进程内分析；线上 PID 先用 live_process_snapshot 定界，再用 monitor_rss 外部观测。"
        if proc["proc_available"]
        else "当前环境缺少 /proc；只能使用离线证据或可复现 workload 的 Python 堆分析。"
    )
    payload = result(
        "success",
        {
            "runtime": {
                "python_version": platform.python_version(),
                "platform": platform.platform(),
                "executable": sys.executable,
            },
            "proc": proc,
            "cgroup": cgroup,
            "readonly_boundary": {
                "default_mode": "readonly",
                "attach_or_ptrace_requires_approval": True,
                "mutation_or_repair_requires_approval": True,
                "ptrace_note": "ptrace_scope 只描述系统边界；本 skill 默认不 attach 线上进程。",
            },
            "recommended_path": recommended_path,
        },
        backend_used="stdlib:/proc-boundary",
        degraded_capabilities=[] if proc["proc_available"] else ["No /proc filesystem; live PID RSS and mapping checks are unavailable."],
        next_steps=[
            "已有 PID 时先运行 live_process_snapshot.py 复核 PID、cgroup、mapping 和子进程范围。",
            "再运行 monitor_rss.py 判断 RSS/Private_Dirty/cgroup/worker 增长形态。",
            "可重启复现时运行 object_growth.py、semantic_probe.py、tracemalloc_probe.py 和 retention_chain.py。",
            "最终报告前运行或读取 correlate_evidence.py，并引用 verdict、confidence_cap 和 missing_evidence。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
