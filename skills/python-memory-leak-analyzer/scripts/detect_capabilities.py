#!/usr/bin/env python3
"""Detect optional tools and safe analysis routes."""

from __future__ import annotations

import argparse
import importlib.util
import os
import platform
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import print_json, result


OPTIONAL_MODULES = ["psutil", "objgraph", "pympler", "memray", "pyrasite"]
OPTIONAL_BINARIES = ["py-spy", "gdb", "dot", "memray"]


def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def read_file(path: str) -> str | None:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return None


def detect_proc() -> dict:
    proc_available = os.path.isdir("/proc")
    ptrace_scope = read_file("/proc/sys/kernel/yama/ptrace_scope")
    return {
        "proc_available": proc_available,
        "smaps_rollup_available": proc_available and os.path.exists("/proc/self/smaps_rollup"),
        "ptrace_scope": ptrace_scope,
        "ptrace_default_ok": ptrace_scope in {None, "0"},
    }


def detect_cgroup() -> dict:
    if os.path.exists("/sys/fs/cgroup/cgroup.controllers"):
        return {
            "version": "v2",
            "memory_current": os.path.exists("/sys/fs/cgroup/memory.current"),
            "memory_max": os.path.exists("/sys/fs/cgroup/memory.max"),
        }
    if os.path.isdir("/sys/fs/cgroup/memory"):
        return {
            "version": "v1",
            "memory_current": os.path.exists("/sys/fs/cgroup/memory/memory.usage_in_bytes"),
            "memory_max": os.path.exists("/sys/fs/cgroup/memory/memory.limit_in_bytes"),
        }
    return {"version": "none", "memory_current": False, "memory_max": False}


def main() -> int:
    parser = argparse.ArgumentParser(description="Detect python-memory-leak-analyzer capability tier.")
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    modules = {name: module_available(name) for name in OPTIONAL_MODULES}
    binaries = {name: shutil.which(name) is not None for name in OPTIONAL_BINARIES}
    proc = detect_proc()
    cgroup = detect_cgroup()
    degraded = []
    upgradable = []

    if not modules["psutil"]:
        degraded.append("psutil missing: monitor_rss uses /proc-only RSS collection")
        upgradable.append({"tool": "psutil", "unlocks": "portable process memory sampling"})
    if not modules["objgraph"]:
        degraded.append("objgraph missing: retention_chain uses stdlib gc.get_referrers text chains")
        upgradable.append({"tool": "objgraph", "unlocks": "richer backref graph rendering"})
    if not modules["pympler"]:
        degraded.append("pympler missing: object_growth uses sys.getsizeof shallow bytes")
        upgradable.append({"tool": "pympler", "unlocks": "deep object size accounting"})
    if not modules["memray"] and not binaries["memray"]:
        degraded.append("memray missing: native leak path remains direction-level only")
        upgradable.append({"tool": "memray", "unlocks": "native allocation capture parsing"})
    if not binaries["py-spy"] and not modules["pyrasite"]:
        degraded.append("online injection tools missing: live process analysis is external-observation only")

    if proc["proc_available"]:
        recommended_path = "可重启/可复现时使用 --script 进程内分析；线上 PID 先用 monitor_rss 外部观测。"
    else:
        recommended_path = "当前环境缺少 /proc；仅可运行 workload 脚本级 Python 堆分析。"

    payload = result(
        "success",
        {
            "capabilities": {
                "modules": modules,
                "binaries": binaries,
                "proc": proc,
                "cgroup": cgroup,
                "python_version": platform.python_version(),
                "platform": platform.platform(),
            },
            "recommended_path": recommended_path,
            "upgradable": upgradable,
        },
        backend_used="stdlib",
        degraded_capabilities=degraded,
        next_steps=[
            "先运行 monitor_rss.py 判断 RSS 增长形态。",
            "可重启复现时运行 object_growth.py 与 tracemalloc_probe.py。",
            "候选对象明确后运行 retention_chain.py，再决定是否做 reachability_probe.py 反事实验证。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
