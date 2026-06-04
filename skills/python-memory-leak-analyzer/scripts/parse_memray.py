#!/usr/bin/env python3
"""Best-effort parser for memray captures or text reports."""

from __future__ import annotations

import argparse
import importlib.util
import os
import re
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import bytes_to_mib, error_payload, print_json, result


def parse_text(path: str, top: int) -> list[dict]:
    rows = []
    pattern = re.compile(r"(?P<bytes>\d[\d,]*)\s+(?P<rest>.+)")
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = pattern.search(line)
            if not match:
                continue
            try:
                value = int(match.group("bytes").replace(",", ""))
            except ValueError:
                continue
            rows.append({"bytes": value, "mib": bytes_to_mib(value), "line": line.strip()[:240]})
    rows.sort(key=lambda item: item["bytes"], reverse=True)
    return rows[:top]


def parse_with_memray(path: str, top: int) -> tuple[list[dict], str]:
    import memray  # type: ignore

    if not hasattr(memray, "FileReader"):
        return [], "memray module has no FileReader in this version"
    reader = memray.FileReader(path)
    counter: Counter[str] = Counter()
    for record in reader.get_allocation_records():
        size = getattr(record, "size", 0)
        stack = getattr(record, "stack_trace", lambda: [])()
        top_frame = "unknown"
        if stack:
            frame = stack[0]
            top_frame = f"{getattr(frame, 'function', '?')} {getattr(frame, 'filename', '?')}:{getattr(frame, 'lineno', '?')}"
        counter[top_frame] += int(size)
    rows = [{"frame": key, "bytes": value, "mib": bytes_to_mib(value)} for key, value in counter.most_common(top)]
    return rows, "memray.FileReader"


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse optional memray native allocation evidence.")
    parser.add_argument("--capture", required=True, help="memray binary capture or text report.")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    if not os.path.isfile(args.capture):
        print_json(error_payload("input", f"capture does not exist: {args.capture}"), args.output)
        return 2

    memray_available = importlib.util.find_spec("memray") is not None
    backend = "text-fallback"
    degraded = []
    try:
        if memray_available:
            rows, backend = parse_with_memray(args.capture, args.top)
        else:
            degraded.append("memray Python package missing; parsing text-like report only.")
            rows = parse_text(args.capture, args.top)
    except Exception as exc:
        degraded.append(f"memray binary parse failed: {exc}; falling back to text scan.")
        rows = parse_text(args.capture, args.top)
        backend = "text-fallback"

    status = "success" if rows else "partial"
    payload = result(
        status,
        {
            "capture": os.path.abspath(args.capture),
            "summary": {
                "verdict": "native_hotspots_observed" if rows else "no_parseable_native_hotspots",
                "row_count": len(rows),
            },
            "hotspots": rows,
        },
        backend_used=backend,
        degraded_capabilities=degraded,
        next_steps=[
            "将 memray 未释放热点与 monitor_rss 的 RSS 净增长对账。",
            "若 capture 是 attach 方式采集，说明只能覆盖 attach 之后的分配。",
            "符号缺失时安装 debug symbols 后重采，或保留 native 方向级结论。",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
