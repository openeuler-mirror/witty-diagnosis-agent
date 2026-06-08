"""Shared configuration and JSON helpers for python-memory-leak-analyzer."""

from __future__ import annotations

import datetime as _dt
import json
import os
import sys
from typing import Any, Dict


CONFIG: Dict[str, Any] = {
    "skill_name": "python-memory-leak-analyzer",
    "skill_version": "0.1.0",
    "monitor": {
        "interval_seconds": 1.0,
        "duration_seconds": 10.0,
        "min_samples": 4,
        "rss_growth_bytes_per_second": 256 * 1024,
        "plateau_tail_ratio": 0.15,
    },
    "live_process": {
        "top_mappings": 20,
        "worker_skew_ratio": 0.6,
    },
    "correlation": {
        "python_heap_ratio_confirm": 0.6,
        "native_heap_ratio_suspect": 0.2,
        "candidate_coverage_ratio": 0.7,
        "transient_peak_bytes": 4 * 1024 * 1024,
        "file_shmem_growth_ratio": 0.6,
        "mapping_surface_ratio": 0.5,
    },
    "object_growth": {
        "iterations": 1000,
        "top": 20,
        "big_container_top": 10,
        "min_count_delta": 10,
        "min_bytes_delta": 64 * 1024,
    },
    "tracemalloc": {
        "iterations": 1000,
        "nframe": 15,
        "top": 20,
        "min_size_diff": 64 * 1024,
    },
    "retention": {
        "iterations": 1000,
        "samples": 3,
        "max_depth": 5,
        "max_referrers": 80,
    },
    "reachability": {
        "iterations": 1000,
        "gc_rounds": 3,
        "reclaimed_ratio_confirm": 0.7,
    },
}


ERROR_CODES = {
    "input": "VALIDATION_INPUT_INVALID",
    "missing": "VALIDATION_PARAMETER_MISSING",
    "permission": "EXECUTION_PERMISSION_DENIED",
    "unavailable": "EXECUTION_RESOURCE_UNAVAILABLE",
    "external": "EXECUTION_EXTERNAL_FAILURE",
}


def utc_now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def repo_skill_metadata() -> Dict[str, Any]:
    return {
        "skill_name": CONFIG["skill_name"],
        "skill_version": CONFIG["skill_version"],
        "timestamp": utc_now(),
        "python": sys.version.split()[0],
        "platform": sys.platform,
    }


def deep_update(base: Dict[str, Any], updates: Dict[str, Any]) -> Dict[str, Any]:
    result = dict(base)
    for key, value in updates.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_update(result[key], value)
        else:
            result[key] = value
    return result


def load_runtime_config(config_path: str | None = None, set_values: list[str] | None = None) -> Dict[str, Any]:
    config = dict(CONFIG)
    if config_path:
        with open(config_path, "r", encoding="utf-8") as handle:
            config = deep_update(config, json.load(handle))
    for item in set_values or []:
        if "=" not in item:
            raise ValueError(f"--set expects key=value, got {item!r}")
        key, raw_value = item.split("=", 1)
        target = config
        parts = key.split(".")
        for part in parts[:-1]:
            target = target.setdefault(part, {})
            if not isinstance(target, dict):
                raise ValueError(f"cannot set nested key {key!r}")
        target[parts[-1]] = parse_scalar(raw_value)
    return config


def parse_scalar(value: str) -> Any:
    lowered = value.lower()
    if lowered in {"true", "false"}:
        return lowered == "true"
    if lowered in {"none", "null"}:
        return None
    try:
        return int(value)
    except ValueError:
        pass
    try:
        return float(value)
    except ValueError:
        return value


def result(
    status: str,
    results: Dict[str, Any],
    *,
    session_id: str = "python-memory-leak-analysis",
    backend_used: str = "stdlib",
    degraded_capabilities: list[str] | None = None,
    next_steps: list[str] | None = None,
    error_code: str | None = None,
    error_message: str | None = None,
) -> Dict[str, Any]:
    verdict = None
    summary = results.get("summary")
    if isinstance(summary, dict):
        raw_verdict = summary.get("verdict")
        if isinstance(raw_verdict, str):
            verdict = raw_verdict
    if verdict is None and status in {"success", "partial", "error"}:
        verdict = status

    payload: Dict[str, Any] = {
        "status": status,
        "session_id": session_id,
        "verdict": verdict,
        "results": results,
        "evidence": results,
        "backend_used": backend_used,
        "degraded_capabilities": degraded_capabilities or [],
        "next_steps": next_steps or [],
        "metadata": repo_skill_metadata(),
    }
    if error_code:
        payload["error_code"] = error_code
    if error_message:
        payload["error_message"] = error_message
    return payload


def print_json(payload: Dict[str, Any], output: str | None = None) -> None:
    text = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    if output:
        os.makedirs(os.path.dirname(os.path.abspath(output)), exist_ok=True)
        with open(output, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            handle.write("\n")
    print(text)


def error_payload(kind: str, message: str, *, details: Dict[str, Any] | None = None) -> Dict[str, Any]:
    return result(
        "error",
        {"details": details or {}},
        error_code=ERROR_CODES.get(kind, "EXECUTION_EXTERNAL_FAILURE"),
        error_message=message,
        next_steps=["修正输入或补齐权限后重跑；不要在证据不足时输出根因结论。"],
    )


def bytes_to_mib(value: int | float | None) -> float | None:
    if value is None:
        return None
    return round(float(value) / 1024.0 / 1024.0, 3)


def load_workload(script_path: str) -> Dict[str, Any]:
    if not script_path:
        raise ValueError("--script is required for in-process Python heap analysis")
    abs_path = os.path.abspath(script_path)
    if not os.path.isfile(abs_path):
        raise FileNotFoundError(abs_path)
    namespace: Dict[str, Any] = {
        "__file__": abs_path,
        "__name__": "mlda_workload",
    }
    with open(abs_path, "rb") as handle:
        code = compile(handle.read(), abs_path, "exec")
    exec(code, namespace)
    return namespace


def run_workload(namespace: Dict[str, Any], iterations: int) -> Any:
    setup = namespace.get("setup")
    if callable(setup):
        setup()
    workload = namespace.get("run_workload")
    if not callable(workload):
        raise ValueError("workload script must define run_workload(iterations)")
    return workload(iterations)
