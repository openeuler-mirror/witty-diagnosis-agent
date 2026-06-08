#!/usr/bin/env python3
"""Discover Python memory-leak evidence from a broad scope."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import error_payload, print_json, result


EVIDENCE_JSON_NAMES = {
    "capabilities.json": "capabilities",
    "discovery.json": "discovery",
    "discovery.initial.json": "discovery_initial",
    "object_growth.json": "object_growth",
    "semantic.json": "semantic",
    "tracemalloc.json": "tracemalloc",
    "retention.json": "retention",
    "reachability_static.json": "reachability_static",
    "reachability_counterfactual.json": "reachability_counterfactual",
    "monitor_rss_pid.json": "monitor_rss_pid",
    "live_process_snapshot.json": "live_process_snapshot",
    "correlation.json": "correlation",
    "metadata.json": "metadata",
    "manifest.json": "metadata",
}

LOG_PATTERNS = (
    re.compile(r"rss_growth_observed|monitor_rss|rss_net_growth", re.IGNORECASE),
    re.compile(r"semantic_probe|dominant_signals|global_registry_retains", re.IGNORECASE),
    re.compile(r"tracemalloc|object_growth|retention_chain", re.IGNORECASE),
    re.compile(r"oom|out of memory|killed process", re.IGNORECASE),
)

PYTHON_PROJECT_FILES = {
    "requirements.txt",
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
    "Pipfile",
    "poetry.lock",
}

MEMRAY_SUFFIXES = {".bin", ".dat"}
REPORT_SUFFIXES = {".md", ".html"}
TEXT_SUFFIXES = {".log", ".txt", ".out", ".err", ".json", ".md", ".html", ".yaml", ".yml"}
REPORT_CONTRACT_NAMES = {"report-contract.md", "report_contract.md", "final-report-contract.md"}


def read_text(path: Path, limit: int = 16000) -> str:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            return handle.read(limit)
    except OSError:
        return ""


def safe_json(path: Path) -> dict[str, Any] | None:
    try:
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else None
    except (OSError, json.JSONDecodeError):
        return None


def rel(path: Path, base: Path | None = None) -> str:
    try:
        if base:
            return str(path.resolve().relative_to(base.resolve()))
    except ValueError:
        pass
    return str(path.resolve())


def is_pid_scope(scope: str) -> int | None:
    text = scope.strip()
    if text.startswith("pid:"):
        text = text[4:]
    if text.isdigit():
        return int(text)
    return None


def inspect_pid(pid: int) -> dict[str, Any]:
    proc = Path("/proc") / str(pid)
    payload: dict[str, Any] = {
        "pid": pid,
        "proc_exists": proc.exists(),
        "recommended_path": "live_pid_external_readonly",
        "confidence_boundary": "RSS/PID evidence alone cannot confirm a Python heap root cause.",
    }
    if not proc.exists():
        payload["status"] = "missing"
        return payload
    payload["status"] = "available"
    for name in ("cmdline", "status", "cwd"):
        path = proc / name
        try:
            if name == "cwd":
                payload[name] = str(path.resolve())
            elif name == "cmdline":
                payload[name] = path.read_bytes().replace(b"\x00", b" ").decode("utf-8", errors="replace").strip()
            else:
                payload[name] = read_text(path, 4000)
        except OSError:
            payload[name] = None
    return payload


def inspect_process_query(query: str, limit: int = 10) -> dict[str, Any]:
    proc_root = Path("/proc")
    payload: dict[str, Any] = {
        "query": query,
        "proc_available": proc_root.exists(),
        "matches": [],
        "recommended_path": "live_pid_external_readonly",
        "confidence_boundary": "Process-name matching only finds targets; it cannot confirm a Python heap root cause.",
    }
    if not proc_root.exists():
        payload["status"] = "proc_unavailable"
        return payload

    needle = query.lower()
    for child in sorted(proc_root.iterdir(), key=lambda item: item.name):
        if not child.name.isdigit():
            continue
        try:
            cmdline = (child / "cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", errors="replace").strip()
            status_text = read_text(child / "status", 2000)
        except OSError:
            continue
        if needle not in cmdline.lower() and needle not in status_text.lower():
            continue
        match: dict[str, Any] = {
            "pid": int(child.name),
            "cmdline": cmdline,
            "status_excerpt": "\n".join(status_text.splitlines()[:8]),
        }
        try:
            match["cwd"] = str((child / "cwd").resolve())
        except OSError:
            match["cwd"] = None
        payload["matches"].append(match)
        if len(payload["matches"]) >= limit:
            break

    payload["status"] = "matched" if payload["matches"] else "no_match"
    return payload


def classify_json(path: Path) -> dict[str, Any] | None:
    role = EVIDENCE_JSON_NAMES.get(path.name)
    if not role and path.name.startswith("discovery") and path.suffix.lower() == ".json":
        role = "discovery"
    data = safe_json(path)
    if not role and data:
        verdict = data.get("verdict") or data.get("results", {}).get("summary", {}).get("verdict")
        backend = data.get("backend_used")
        if verdict or backend:
            role = "diagnostic_json"
    if not role:
        return None
    summary = data.get("results", {}).get("summary") if data else None
    discovery_recommendation = None
    if data and role == "discovery":
        recommendation = data.get("results", {}).get("recommendation")
        if isinstance(recommendation, dict):
            discovery_recommendation = {
                key: recommendation.get(key)
                for key in ("recommended_path", "primary_evidence_dir", "confidence_boundary")
                if recommendation.get(key) is not None
            }
    return {
        "path": str(path.resolve()),
        "role": role,
        "verdict": data.get("verdict") if data else None,
        "backend_used": data.get("backend_used") if data else None,
        "summary": summary if isinstance(summary, dict) else None,
        "recommendation": discovery_recommendation,
    }


def classify_log(path: Path) -> dict[str, Any] | None:
    if path.suffix.lower() not in {".log", ".out", ".err", ".txt"}:
        return None
    text = read_text(path)
    hits = []
    for pattern in LOG_PATTERNS:
        if pattern.search(text):
            hits.append(pattern.pattern)
    if not hits and "python" not in path.name.lower() and "memory" not in path.name.lower() and "leak" not in path.name.lower():
        return None
    return {
        "path": str(path.resolve()),
        "role": "log",
        "size_bytes": path.stat().st_size,
        "signals": hits,
    }


def classify_python(path: Path) -> dict[str, Any] | None:
    if path.suffix.lower() != ".py":
        return None
    text = read_text(path)
    has_workload = "def run_workload" in text
    has_setup = "def setup" in text
    leak_terms = [term for term in ("lru_cache", "threading.local", "asyncio", "weakref.finalize", "gc.DEBUG_SAVEALL") if term in text]
    if not has_workload and not leak_terms:
        return None
    return {
        "path": str(path.resolve()),
        "role": "workload_script" if has_workload else "python_source",
        "defines_run_workload": has_workload,
        "defines_setup": has_setup,
        "signals": leak_terms,
    }


def classify_report(path: Path) -> dict[str, Any] | None:
    if path.suffix.lower() not in REPORT_SUFFIXES:
        return None
    text = read_text(path)
    if path.name in REPORT_CONTRACT_NAMES or "final_report_must_include" in text:
        return {
            "path": str(path.resolve()),
            "role": "report_contract",
            "evidence_use": "report_acceptance_gate",
            "size_bytes": path.stat().st_size,
            "contract_focus": "evidence_boundary_and_html_same_source",
        }
    lower = text.lower()
    has_python = "python" in lower
    has_memory = "memory" in lower or "内存" in text or "rss" in lower
    has_leak = "leak" in lower or "泄漏" in text or "泄露" in text
    if not (has_python and has_memory and has_leak):
        return None
    return {
        "path": str(path.resolve()),
        "role": "diagnosis_report",
        "evidence_use": "context_only",
        "size_bytes": path.stat().st_size,
    }


def classify_file(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if path.name in PYTHON_PROJECT_FILES:
        rows.append({"path": str(path.resolve()), "role": "python_project_file"})
    if path.name == "run.sh":
        text = read_text(path)
        if "run-edge" in text or "python-memory-leak-analyzer" in text:
            rows.append({"path": str(path.resolve()), "role": "test_runner", "supports_edge_cases": "run-edge" in text})
    if path.name in {"scenario_manifest.json", "manifest.json", "metadata.json"}:
        row = classify_json(path)
        rows.append(row or {"path": str(path.resolve()), "role": "manifest"})
    elif path.suffix.lower() == ".json":
        row = classify_json(path)
        if row:
            rows.append(row)
    log_row = classify_log(path)
    if log_row:
        rows.append(log_row)
    py_row = classify_python(path)
    if py_row:
        rows.append(py_row)
    report_row = classify_report(path)
    if report_row:
        rows.append(report_row)
    lower_name = path.name.lower()
    if "memray" in lower_name or path.suffix.lower() in MEMRAY_SUFFIXES:
        rows.append({"path": str(path.resolve()), "role": "memray_candidate", "suffix": path.suffix.lower()})
    return rows


def iter_files(scope: Path, max_files: int, max_depth: int) -> list[Path]:
    if scope.is_file():
        return [scope]
    files = []
    base_parts = len(scope.resolve().parts)
    skip_dirs = {".git", "node_modules", "__pycache__", ".venv", "venv", "dist", "build"}
    for root, dirs, names in os.walk(scope):
        root_path = Path(root)
        depth = len(root_path.resolve().parts) - base_parts
        dirs[:] = [item for item in dirs if item not in skip_dirs and depth < max_depth]
        for name in sorted(names):
            path = root_path / name
            if path.suffix.lower() not in TEXT_SUFFIXES and path.name not in PYTHON_PROJECT_FILES and path.suffix.lower() not in MEMRAY_SUFFIXES:
                continue
            files.append(path)
            if len(files) >= max_files:
                return files
    return files


def scan_path(scope: Path, max_files: int, max_depth: int) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "scope": str(scope.resolve()),
        "exists": scope.exists(),
        "kind": "directory" if scope.is_dir() else "file" if scope.is_file() else "missing",
        "findings": [],
    }
    if not scope.exists():
        return payload
    for path in iter_files(scope, max_files, max_depth):
        try:
            rows = classify_file(path)
        except OSError:
            rows = []
        payload["findings"].extend(rows)
    return payload


def exclude_output_findings(payload: dict[str, Any], output: Path | None) -> None:
    if not output:
        return
    try:
        output_path = output.resolve()
    except OSError:
        output_path = output.absolute()
    kept = []
    for finding in payload.get("findings", []):
        try:
            if Path(str(finding.get("path", ""))).resolve() == output_path:
                continue
        except OSError:
            pass
        kept.append(finding)
    payload["findings"] = kept


def group_by_dir(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[str, dict[str, Any]] = defaultdict(lambda: {"roles": defaultdict(list), "score": 0})
    for finding in findings:
        path = Path(str(finding["path"]))
        group_dir = str(path.parent.resolve())
        group = groups[group_dir]
        role = str(finding.get("role"))
        group["roles"][role].append(finding)
    rows = []
    for directory, group in groups.items():
        roles = group["roles"]
        score = 0
        if roles.get("discovery"):
            score += 12
        if roles.get("semantic"):
            score += 40
        if roles.get("correlation"):
            score += 45
        if roles.get("live_process_snapshot"):
            score += 25
        if roles.get("object_growth"):
            score += 25
        if roles.get("retention"):
            score += 20
        if roles.get("tracemalloc"):
            score += 20
        if roles.get("monitor_rss_pid"):
            score += 20
        if roles.get("log"):
            score += 10
        if roles.get("workload_script"):
            score += 10
        if roles.get("test_runner"):
            score += 8
        if roles.get("memray_candidate"):
            score += 12
        if roles.get("report_contract"):
            score += 8
        # Existing diagnosis reports are useful context or archive targets, but
        # they must not outrank current-scope logs and structured evidence.
        role_summary = {role: len(items) for role, items in roles.items()}
        discovery_recommendations = [
            item["recommendation"]
            for item in roles.get("discovery", [])
            if isinstance(item.get("recommendation"), dict)
        ]
        rows.append(
            {
                "directory": directory,
                "score": score,
                "role_summary": role_summary,
                "discovery_recommendations": discovery_recommendations,
                "key_files": {
                    role: [item["path"] for item in items[:3]]
                    for role, items in roles.items()
                    if role in {"discovery", "correlation", "live_process_snapshot", "semantic", "object_growth", "retention", "tracemalloc", "monitor_rss_pid", "log", "workload_script", "test_runner", "memray_candidate", "diagnosis_report", "report_contract"}
                },
            }
        )
    rows.sort(key=lambda item: item["score"], reverse=True)
    return rows


def recommendation(groups: list[dict[str, Any]], pids: list[dict[str, Any]], process_scopes: list[dict[str, Any]]) -> dict[str, Any]:
    process_matches = [
        match
        for scope in process_scopes
        for match in scope.get("matches", [])
        if isinstance(match, dict)
    ]
    if (pids or process_matches) and not groups:
        pid_hint = ", ".join(str(item.get("pid")) for item in pids if item.get("status") == "available")
        if not pid_hint:
            pid_hint = ", ".join(str(match.get("pid")) for match in process_matches[:5])
        return {
            "recommended_path": "live_pid_external_readonly",
            "next_actions": [
                f"Run live_process_snapshot.py --pid <PID>, then monitor_rss.py --pid <PID>; candidate PIDs: {pid_hint or '<PID>'}.",
                "Do not claim Python root cause without heap and retention evidence; run correlate_evidence.py before final reporting.",
            ],
            "minimal_questions": ["是否允许重启复现或提供故障目录/日志目录？"],
        }
    if not groups:
        return {
            "recommended_path": "insufficient_evidence",
            "next_actions": ["Ask for a directory, PID, service name, or log bundle path."],
            "minimal_questions": ["故障环境范围在哪里：目录、PID、服务名或容器名？"],
        }
    top = groups[0]
    roles = top["role_summary"]
    actions = []
    questions = []
    discovery_recommendations = top.get("discovery_recommendations") or []
    current_evidence_roles = {
        "capabilities",
        "discovery",
        "semantic",
        "correlation",
        "live_process_snapshot",
        "object_growth",
        "retention",
        "tracemalloc",
        "monitor_rss_pid",
        "log",
        "workload_script",
        "test_runner",
        "memray_candidate",
        "diagnostic_json",
        "metadata",
        "report_contract",
    }
    if roles.get("diagnosis_report") and not any(roles.get(role) for role in current_evidence_roles):
        return {
            "recommended_path": "report_context_only",
            "primary_evidence_dir": top["directory"],
            "next_actions": [
                "Do not use historical Markdown/HTML reports as current root-cause evidence.",
                "Ask for or discover the current scope directory, PID, service name, logs, or structured evidence bundle.",
            ],
            "minimal_questions": ["当前故障环境范围在哪里：目录、PID、服务名或容器名？"],
            "confidence_boundary": "Existing reports can be archive/context only; they cannot confirm the current scenario root cause.",
        }
    if roles.get("correlation"):
        path = "correlated_evidence_bundle"
        actions.append("Read correlation.json first; final report must cite its verdict, confidence_cap, and missing_evidence before root-cause wording.")
        if roles.get("report_contract"):
            actions.append("Read report-contract.md before final reporting; verify evidence boundary wording and generate HTML from the same Markdown basename.")
        if roles.get("live_process_snapshot"):
            actions.append("Use live_process_snapshot.json to confirm PID, cgroup, child-process, and mapping scope.")
        if roles.get("object_growth") or roles.get("tracemalloc") or roles.get("retention") or roles.get("semantic"):
            actions.append("Cross-check correlation.json against heap, semantic, allocation, and retention JSON before confirming Python retained leak.")
    elif roles.get("semantic") and roles.get("object_growth") and roles.get("retention"):
        path = "offline_evidence_bundle"
        actions.append("Run correlate_evidence.py if monitor/snapshot/heap evidence is available, then read semantic.json, object_growth.json, retention.json, and tracemalloc.json.")
    elif discovery_recommendations:
        path = discovery_recommendations[0].get("recommended_path") or "offline_evidence_bundle"
        actions.append("Read discovery.json, then verify the referenced primary_evidence_dir against files currently present in scope.")
    elif roles.get("workload_script"):
        path = "reproducible_workload"
        workload = top.get("key_files", {}).get("workload_script", ["<script>"])[0]
        actions.extend(
            [
                f"Run object_growth.py --script {workload}",
                f"Run semantic_probe.py --script {workload}",
                f"Run tracemalloc_probe.py --script {workload}",
            ]
        )
    elif roles.get("live_process_snapshot") or roles.get("monitor_rss_pid") or roles.get("log"):
        path = "logs_only_or_external_rss"
        actions.append("Use live_process_snapshot and monitor_rss evidence to classify process/cgroup/mapping growth shape; keep confidence capped without heap/retention evidence.")
        questions.append("是否允许提供可复现 workload、heap/tracemalloc 快照或 native allocation capture？")
    elif roles.get("memray_candidate"):
        path = "memray_capture"
        actions.append("Run parse_memray.py or inspect memray report before Python heap conclusions.")
    else:
        path = "source_only"
        actions.append("Statically inspect source for globals, caches, registries, closures, thread-local state, generators, and tasks.")
        questions.append("是否有复现命令或运行日志可补充？")
    return {
        "recommended_path": path,
        "primary_evidence_dir": top["directory"],
        "next_actions": actions,
        "minimal_questions": questions,
        "confidence_boundary": "Write conclusions as confirmed only when allocation, semantic retention, and reachability evidence agree.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Discover Python memory-leak evidence from broad path/PID scopes.")
    parser.add_argument("scope", nargs="*", help="Directory, file, PID, pid:<PID>, service name, or broad scope. Defaults to current directory.")
    parser.add_argument("--max-files", type=int, default=600)
    parser.add_argument("--max-depth", type=int, default=6)
    parser.add_argument("--output", help="Write JSON output to this path.")
    args = parser.parse_args()

    path_payloads = []
    pid_payloads = []
    process_payloads = []
    all_findings: list[dict[str, Any]] = []
    scopes = args.scope or ["."]
    output_path = Path(args.output) if args.output else None
    try:
        for raw_scope in scopes:
            pid = is_pid_scope(raw_scope)
            if pid is not None:
                pid_payloads.append(inspect_pid(pid))
                continue
            scope_path = Path(raw_scope)
            payload = scan_path(scope_path, args.max_files, args.max_depth)
            exclude_output_findings(payload, output_path)
            path_payloads.append(payload)
            all_findings.extend(payload.get("findings", []))
            if not scope_path.exists() and raw_scope.strip():
                process_payload = inspect_process_query(raw_scope)
                process_payloads.append(process_payload)
    except Exception as exc:
        print_json(error_payload("input", str(exc), details={"scope": scopes}), args.output)
        return 2

    groups = group_by_dir(all_findings)
    rec = recommendation(groups, pid_payloads, process_payloads)
    payload = result(
        "success" if groups or pid_payloads or process_payloads else "partial",
        {
            "default_scope_used": not bool(args.scope),
            "scopes": path_payloads,
            "pid_scopes": pid_payloads,
            "process_scopes": process_payloads,
            "candidate_evidence_dirs": groups[:10],
            "recommendation": rec,
            "finding_count": len(all_findings),
        },
        backend_used="stdlib:filesystem+/proc",
        degraded_capabilities=[
            "Discovery identifies evidence and routes; it does not prove root cause by itself.",
            "PID scopes remain external-readonly unless explicit attach/restart approval exists.",
        ],
        next_steps=[
            "Start from recommendation.primary_evidence_dir when present.",
            "For offline bundles, read discovery.json and semantic.json before asking the user for more logs.",
            "For PID-only scopes, collect RSS externally and keep root-cause confidence capped.",
        ],
    )
    print_json(payload, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
