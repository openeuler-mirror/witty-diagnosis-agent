#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CLI tool for calling the /json/search endpoint of euler-copilot-rag.

Supports semantic search with configurable semantic_keys and structured
content-field filters via logical expressions.
"""

from __future__ import annotations

import argparse
import json
import shlex
import sys
from pathlib import Path
from typing import Any

import requests


DEFAULT_BASE_URL = "http://localhost:9988"
DEFAULT_TOP_K = 5
DEFAULT_RATIO = 0.3

VALID_NAME_OPS = {"eq", "ne", "like", "like_left", "like_right", "in", "not_in"}
VALID_FILTER_OPS = {
    "eq",
    "ne",
    "like",
    "like_left",
    "like_right",
    "in",
    "not_in",
    "gt",
    "gte",
    "lt",
    "lte",
    "between",
}
VALID_SCHEMA_TYPES = {"string", "number", "integer", "boolean"}
VALID_VERSION_OPS = {
    "eq",
    "ne",
    "like",
    "like_left",
    "like_right",
    "in",
    "not_in",
    "gt",
    "gte",
    "lt",
    "lte",
    "between",
}
VALID_LOGIC_OPS = {"and", "or", "and_not", "or_not"}
VALID_AUTH_HEADERS = {"access_key", "authorization", "both"}


def parse_scalar(value: str, schema_type: str) -> Any:
    """Parse a scalar CLI string according to the requested schema type."""
    if schema_type == "string":
        return value
    if schema_type == "integer":
        try:
            return int(value)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"Expected integer value, got: {value!r}") from exc
    if schema_type == "number":
        try:
            return float(value)
        except ValueError as exc:
            raise argparse.ArgumentTypeError(f"Expected numeric value, got: {value!r}") from exc
    if schema_type == "boolean":
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "y"}:
            return True
        if normalized in {"false", "0", "no", "n"}:
            return False
        raise argparse.ArgumentTypeError(f"Expected boolean value, got: {value!r}")
    raise argparse.ArgumentTypeError(f"Unsupported schema type: {schema_type!r}")


def parse_value(value: str | None, operator: str, schema_type: str = "string") -> Any:
    """Parse CLI string value into the proper payload type."""
    if value is None:
        return None
    if operator in {"in", "not_in"}:
        return [parse_scalar(v.strip(), schema_type) for v in value.split(",")]
    if operator == "between":
        parts = [v.strip() for v in value.split(",")]
        if len(parts) != 2:
            raise argparse.ArgumentTypeError(
                f"Operator '{operator}' requires exactly two comma-separated values, got: {value!r}"
            )
        return [parse_scalar(v, schema_type) for v in parts]
    return parse_scalar(value, schema_type)


def build_condition(field: str, value: Any, operator: str, schema_type: str) -> dict[str, Any]:
    """Build a single Condition object."""
    return {
        "field": field,
        "type": schema_type,
        "operator": operator,
        "value": value,
    }


def parse_filter(raw_filter: str) -> dict[str, Any]:
    """Parse --filter field[:operator[:type]]=value into a Condition object."""
    if "=" not in raw_filter:
        raise argparse.ArgumentTypeError(
            "Filter must use field[:operator[:type]]=value format, "
            f"got: {raw_filter!r}"
        )

    lhs, raw_value = raw_filter.split("=", 1)
    parts = [part.strip() for part in lhs.split(":")]
    if not parts or not parts[0]:
        raise argparse.ArgumentTypeError(f"Filter field is required, got: {raw_filter!r}")

    field = parts[0]
    operator = parts[1] if len(parts) >= 2 and parts[1] else "eq"
    schema_type = parts[2] if len(parts) >= 3 and parts[2] else "string"

    if len(parts) > 3:
        raise argparse.ArgumentTypeError(
            "Filter must use field[:operator[:type]]=value format, "
            f"got: {raw_filter!r}"
        )
    if operator not in VALID_FILTER_OPS:
        raise argparse.ArgumentTypeError(
            f"Unsupported filter operator {operator!r}; "
            f"choose from {sorted(VALID_FILTER_OPS)}"
        )
    if schema_type not in VALID_SCHEMA_TYPES:
        raise argparse.ArgumentTypeError(
            f"Unsupported filter type {schema_type!r}; "
            f"choose from {sorted(VALID_SCHEMA_TYPES)}"
        )

    value = parse_value(raw_value, operator, schema_type)
    return build_condition(field, value, operator, schema_type)


def wrap_logical_expression(expression: Any, logic_op: str) -> Any:
    """Ensure logical_expression uses the API's {operator, expressions} shape."""
    if expression is None:
        return None
    if isinstance(expression, dict) and "expressions" in expression:
        return expression
    if isinstance(expression, dict) and {"field", "operator", "value"}.issubset(expression):
        return {"operator": logic_op, "expressions": [expression]}
    return expression


def build_logical_expression(
    name: str | None,
    name_op: str,
    kernel_version: str | None,
    kernel_version_op: str,
    filters: list[str] | None,
    logic_op: str,
) -> dict[str, Any] | None:
    """Build the logical expression payload for simple content-field filters."""
    expressions: list[dict[str, Any]] = []

    if name is not None:
        value = parse_value(name, name_op)
        expressions.append(build_condition("name", value, name_op, "string"))

    if kernel_version is not None:
        value = parse_value(kernel_version, kernel_version_op)
        expressions.append(build_condition("kernel_version", value, kernel_version_op, "string"))

    for raw_filter in filters or []:
        expressions.append(parse_filter(raw_filter))

    if not expressions:
        return None

    return {"operator": logic_op, "expressions": expressions}


def load_complex_logical_expression(args: argparse.Namespace) -> Any:
    """Load a user-provided multi-level nested logical expression."""
    if args.logical_expression_file:
        path = Path(args.logical_expression_file)
        if not path.exists():
            raise argparse.ArgumentTypeError(
                f"Logical expression file not found: {path}"
            )
        try:
            with path.open("r", encoding="utf-8") as f:
                data = json.load(f)
        except json.JSONDecodeError as exc:
            raise argparse.ArgumentTypeError(
                f"Invalid JSON in logical expression file: {exc}"
            ) from exc
        return data

    if args.logical_expression:
        try:
            return json.loads(args.logical_expression)
        except json.JSONDecodeError as exc:
            raise argparse.ArgumentTypeError(
                f"Invalid JSON in --logical-expression: {exc}"
            ) from exc

    return None


def build_payload(args: argparse.Namespace) -> dict[str, Any]:
    """Build the SearchJsonRequest payload from CLI arguments."""
    if args.semantic_only:
        logical_expression = None
    else:
        simple_expression = build_logical_expression(
            name=args.name,
            name_op=args.name_op,
            kernel_version=args.kernel_version,
            kernel_version_op=args.kernel_version_op,
            filters=args.filter,
            logic_op=args.operator,
        )

        complex_expression = wrap_logical_expression(
            load_complex_logical_expression(args),
            args.operator,
        )

        if complex_expression is not None and simple_expression is not None:
            # Combine simple filters with the complex expression under the chosen operator.
            logical_expression = {
                "operator": args.operator,
                "expressions": [simple_expression, complex_expression],
            }
        elif complex_expression is not None:
            logical_expression = complex_expression
        else:
            logical_expression = simple_expression

    search_config: dict[str, Any] = {
        "kb_id": args.kb_id,
        "query": args.query,
        "top_k": args.top_k,
        "ratio": args.ratio,
    }

    if logical_expression is not None:
        search_config["logical_expression"] = logical_expression

    if args.banned_json_ids:
        search_config["banned_json_ids"] = args.banned_json_ids.split(",")

    if args.semantic_keys:
        search_config["semantic_keys"] = [
            [k.strip() for k in group.split(".")] for group in args.semantic_keys.split(",")
        ]

    return {
        "need_trace": args.need_trace,
        "search_json_configs": [search_config],
    }


def build_headers(access_key: str, auth_header: str) -> dict[str, str]:
    """Build request headers for the configured auth style."""
    headers = {"Content-Type": "application/json"}
    if auth_header in {"access_key", "both"}:
        headers["access_key"] = access_key
    if auth_header in {"authorization", "both"}:
        headers["Authorization"] = f"Bearer {access_key}"
    return headers


def build_curl_command(base_url: str, access_key: str, payload: dict[str, Any], auth_header: str) -> str:
    """Build a shell-safe curl command for handoff/debugging."""
    url = f"{base_url.rstrip('/')}/json/search"
    parts = ["curl", "-sS", "-X", "POST", url]
    for key, value in build_headers(access_key, auth_header).items():
        parts.extend(["-H", f"{key}: {value}"])
    parts.extend(["-d", json.dumps(payload, ensure_ascii=False)])
    return " ".join(shlex.quote(part) for part in parts)


def send_request(
    base_url: str,
    access_key: str,
    payload: dict[str, Any],
    timeout: int,
    auth_header: str,
) -> dict[str, Any]:
    """Send POST request to /json/search and return JSON response."""
    url = f"{base_url.rstrip('/')}/json/search"
    headers = build_headers(access_key, auth_header)

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=timeout)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.HTTPError as exc:
        detail = ""
        try:
            detail = exc.response.json()
        except Exception:
            detail = exc.response.text
        raise SystemExit(f"HTTP {exc.response.status_code}: {detail}") from exc
    except requests.exceptions.ConnectionError as exc:
        raise SystemExit(f"Failed to connect to {url}: {exc}") from exc
    except requests.exceptions.Timeout as exc:
        raise SystemExit(f"Request timed out after {timeout}s: {exc}") from exc


def pick_first(data: Any, paths: list[str]) -> str:
    """Return the first non-empty value found through dotted dict paths."""
    for path in paths:
        current = data
        for part in path.split("."):
            if not isinstance(current, dict):
                current = None
                break
            current = current.get(part)
        if current not in (None, ""):
            return str(current)
    return ""


def collect_hits(response: dict[str, Any]) -> list[dict[str, Any]]:
    """Collect json hit objects from common /json/search response shapes."""
    result = response.get("result")
    if isinstance(result, dict):
        if isinstance(result.get("jsons"), list):
            return [hit for hit in result["jsons"] if isinstance(hit, dict)]
        if isinstance(result.get("results"), list):
            hits: list[dict[str, Any]] = []
            for item in result["results"]:
                if isinstance(item, dict) and isinstance(item.get("jsons"), list):
                    hits.extend(hit for hit in item["jsons"] if isinstance(hit, dict))
            return hits
    if isinstance(result, list):
        hits = []
        for item in result:
            if isinstance(item, dict) and isinstance(item.get("jsons"), list):
                hits.extend(hit for hit in item["jsons"] if isinstance(hit, dict))
        return hits
    return []


def summarize_response(response: dict[str, Any], limit: int = 5) -> str:
    """Build a concise, agent-friendly validation summary."""
    code = response.get("code")
    message = response.get("message")
    hits = collect_hits(response)
    lines = [f"code={code} message={message} hits={len(hits)}"]

    for index, hit in enumerate(hits[:limit], start=1):
        content = hit.get("content") if isinstance(hit.get("content"), dict) else {}
        title = pick_first(hit, ["title", "content.title", "metadata.title"])
        kernel_version = pick_first(hit, ["kernel_version", "content.kernel_version"])
        name = pick_first(hit, ["name", "filename", "json_name"])

        if not title and content:
            title = pick_first(content, ["title", "name"])

        parts = [f"{index}."]
        if name:
            parts.append(f"name={name}")
        if title:
            parts.append(f"title={title}")
        if kernel_version:
            parts.append(f"kernel_version={kernel_version}")
        lines.append(" ".join(parts))

    return "\n".join(lines)


def create_parser() -> argparse.ArgumentParser:
    """Create and return the argument parser."""
    parser = argparse.ArgumentParser(
        prog="search-json",
        description=(
            "Call euler-copilot-rag /json/search endpoint. "
            "Build semantic searches and structured content-field filters "
            "for JSON knowledge bases."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Semantic search over selected JSON fields
  python search_json.py --kb-id kb_001 --access-key TOKEN \\
      --query "磁盘无法识别" \\
      --semantic-keys title,phenomenon,root_cause,solution,content \\
      --semantic-only --summary

  # Semantic search plus a content-field filter
  python search_json.py --kb-id kb_001 --access-key TOKEN \\
      --query "磁盘无法识别" \\
      --semantic-keys title,phenomenon,root_cause,solution,content \\
      --filter kernel_version:eq=3.0.18 --summary

  # Print an equivalent curl command for handoff
  python search_json.py --kb-id kb_001 --access-key '<ACCESS_KEY>' \\
      --query "磁盘无法识别" \\
      --semantic-keys title,phenomenon,root_cause,solution,content \\
      --print-curl

  # Multi-level nested logical expression via JSON string
  python search_json.py --kb-id kb_001 --access-key TOKEN \\
      --logical-expression '{"operator":"or","expressions":[{"field":"title","type":"string","operator":"like","value":"RAID"},{"field":"kernel_version","type":"string","operator":"eq","value":"3.0.18"}]}'
        """.strip(),
    )

    parser.add_argument(
        "--kb-id",
        required=True,
        help="Knowledge base ID to search in.",
    )
    parser.add_argument(
        "--access-key",
        required=True,
        help="Access key for authorization.",
    )
    parser.add_argument(
        "--auth-header",
        default="access_key",
        choices=sorted(VALID_AUTH_HEADERS),
        help=(
            "Auth header style: access_key, authorization, or both. "
            "Default: access_key"
        ),
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help=f"Base URL of the rag_core service. Default: {DEFAULT_BASE_URL}",
    )
    parser.add_argument(
        "-q", "--query",
        default="",
        help="Semantic query text (searched against content).",
    )

    # Name filter
    parser.add_argument(
        "--name",
        help="Filter value for the 'name' field.",
    )
    parser.add_argument(
        "--name-op",
        default="eq",
        choices=sorted(VALID_NAME_OPS),
        help="Operator for the name filter. Default: eq",
    )

    # Kernel version filter
    parser.add_argument(
        "--kernel-version",
        help="Filter value for the 'kernel_version' field (string).",
    )
    parser.add_argument(
        "--kernel-version-op",
        default="eq",
        choices=sorted(VALID_VERSION_OPS),
        help="Operator for the kernel_version filter. Default: eq",
    )
    parser.add_argument(
        "--filter",
        action="append",
        help=(
            "Generic content-field filter in field[:operator[:type]]=value format. "
            "Examples: kernel_version:eq=3.0.18, title:like=megaraid_sas, "
            "priority:gte:number=3. Can be repeated."
        ),
    )

    # Logical combination
    parser.add_argument(
        "-o", "--operator",
        default="and",
        choices=sorted(VALID_LOGIC_OPS),
        help="Logical operator combining simple and complex conditions. Default: and",
    )
    parser.add_argument(
        "-e", "--logical-expression",
        help=(
            "Raw JSON for a multi-level nested logical expression. "
            "When provided, it is combined with simple --name/--kernel-version filters via --operator."
        ),
    )
    parser.add_argument(
        "-f", "--logical-expression-file",
        help="Path to a JSON file containing a multi-level nested logical expression.",
    )

    # Search tuning
    parser.add_argument(
        "--top-k",
        type=int,
        default=DEFAULT_TOP_K,
        help=f"Number of results to return. Default: {DEFAULT_TOP_K}",
    )
    parser.add_argument(
        "--ratio",
        type=float,
        default=DEFAULT_RATIO,
        help=f"Semantic search result ratio (0-1). Default: {DEFAULT_RATIO}",
    )
    parser.add_argument(
        "--banned-json-ids",
        help="Comma-separated list of JSON IDs to exclude.",
    )
    parser.add_argument(
        "--semantic-keys",
        help="Comma-separated semantic search keys, use dots for nested paths (e.g. content,name).",
    )
    parser.add_argument(
        "--need-trace",
        action="store_true",
        help="Return trace information in the response.",
    )
    parser.add_argument(
        "--semantic-only",
        action="store_true",
        help=(
            "Force a semantic-only search and omit logical_expression even if "
            "filter arguments are present."
        ),
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="Request timeout in seconds. Default: 30",
    )
    parser.add_argument(
        "--print-payload",
        action="store_true",
        help="Print the request payload without sending it.",
    )
    parser.add_argument(
        "--print-curl",
        action="store_true",
        help="Print an equivalent curl command without sending it.",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help=(
            "Print a concise validation summary instead of the full JSON response "
            "(code, message, hit count, and top result names/titles)."
        ),
    )

    return parser


def validate_args(args: argparse.Namespace) -> None:
    """Validate CLI arguments."""
    if not (0 <= args.ratio <= 1):
        raise argparse.ArgumentError(None, f"--ratio must be between 0 and 1, got {args.ratio}")
    if args.top_k <= 0:
        raise argparse.ArgumentError(None, f"--top-k must be positive, got {args.top_k}")


def main() -> int:
    parser = create_parser()
    args = parser.parse_args()

    try:
        validate_args(args)
    except argparse.ArgumentError as exc:
        parser.error(str(exc))

    payload = build_payload(args)

    if args.print_payload:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    if args.print_curl:
        print(build_curl_command(args.base_url, args.access_key, payload, args.auth_header))
        return 0

    result = send_request(args.base_url, args.access_key, payload, args.timeout, args.auth_header)
    if args.summary:
        print(summarize_response(result))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
