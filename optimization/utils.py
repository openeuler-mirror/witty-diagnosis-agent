import datetime
import re
import json
import os
from typing import List, Dict, Optional
from pathlib import Path
import urllib.request
import urllib.error
import json as json_module
from tabulate import tabulate


def get_skill_name_from_md(content: str) -> str:
    """Extract skill name from SKILL.md content."""
    # Try YAML frontmatter first
    match = re.search(r"^name:\s+(.+)$", content, re.MULTILINE)
    if match:
        return match.group(1).strip()

    # Fallback to header
    match = re.search(r"^#\s+(.+)$", content, re.MULTILINE)
    if match:
        return match.group(1).strip().lower().replace(" ", "-")
    return "unknown_skill"


def update_skill_name_in_md(content: str, new_name: str) -> str:
    """Update skill name in SKILL.md content."""
    # Try YAML frontmatter first
    pattern = r"^name:\s+(.+)$"
    match = re.search(pattern, content, re.MULTILINE)
    if match:
        return re.sub(
            pattern, f"name: {new_name}", content, count=1, flags=re.MULTILINE
        )

    # Fallback to header (only if name is in header)
    pattern = r"^#\s+(.+)$"
    match = re.search(pattern, content, re.MULTILINE)
    if match:
        return re.sub(pattern, f"# {new_name}", content, count=1, flags=re.MULTILINE)

    return content


def save_optimization_history(
    history: List[Dict],
    target_skill_file: Path,
    output_dir: Optional[Path] = None,
    skill_name: Optional[str] = None,
):
    """Save GEPA optimization history to a JSON file."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

    if output_dir:
        # If output_dir is specified, use it.
        # Filename should include skill_name to avoid conflicts.
        name_part = f"_{skill_name}" if skill_name else ""
        filename = f"optimization_history{name_part}_{timestamp}.json"
        history_file = output_dir / filename
    else:
        # Fallback to original behavior: save alongside the skill file
        history_file = target_skill_file.with_name(
            f"optimization_history_{timestamp}.json"
        )

    try:
        # Ensure parent dir exists (if output_dir is used)
        if output_dir and not output_dir.exists():
            output_dir.mkdir(parents=True, exist_ok=True)

        with open(history_file, "w", encoding="utf-8") as f:
            json.dump(history, f, indent=2, ensure_ascii=False)
        print(f"Optimization history saved to: {history_file}")
    except Exception as e:
        print(f"Failed to save optimization history: {e}")

    # --- Print Summary Table ---
    try:
        from tabulate import tabulate
    except ImportError:
        print("tabulate module not found. Please install it with `uv add tabulate`.")
        return

    # Define dimensions (5 core dimensions)
    dimensions = [
        "职责明确性",
        "结构规范性",
        "指令适配性",
        "内容一致性",
        "风险可控性",
    ]

    # Prepare table headers
    headers = ["Round", "Iter", "Avg Score"] + dimensions

    # Prepare table rows
    table_data = []
    for entry in history:
        round_num = entry.get("round", "?")
        # Assuming Iteration is same as Round for now as we don't track separate external iteration
        iter_num = entry.get("iteration", round_num)
        avg_score = entry.get("average_score", 0.0)

        # Extract dimension scores
        details = entry.get("details", [])
        # Create a map for quick lookup
        score_map = {d.get("dimension"): d.get("score", "N/A") for d in details}

        row = [
            round_num,
            iter_num,
            f"{avg_score:.2f}",
        ]

        for dim in dimensions:
            score = score_map.get(dim, "-")
            if isinstance(score, (int, float)):
                row.append(f"{score:.1f}")
            else:
                row.append(str(score))

        table_data.append(row)

    print("\n" + "=" * 60)
    print(tabulate(table_data, headers=headers, tablefmt="grid"))
    print("=" * 60)


def send_skill_scores(scores: Dict[str, float]) -> bool:
    """
    Send multiple skill scores to ops board via POST request.

    Args:
        scores: Dictionary of skill names to scores (normalized 0-1 or raw)

    Returns:
        True if successful, False otherwise
    """
    ops_board_url = os.environ.get("OPS_BOARD_URL")
    if not ops_board_url:
        print(
            "Warning: OPS_BOARD_URL environment variable not set. Skipping score sending."
        )
        return False

    if not ops_board_url.startswith(("http://", "https://")):
        ops_board_url = f"http://{ops_board_url}"

    data = json_module.dumps(scores).encode("utf-8")

    req = urllib.request.Request(
        url=ops_board_url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status in (200, 201, 202):
                print(f"Successfully sent scores to {ops_board_url}")
                return True
            else:
                print(f"Failed to send score. HTTP status: {response.status}")
                return False
    except urllib.error.URLError as e:
        print(f"Network error while sending score: {e}")
        return False
    except Exception as e:
        print(f"Unexpected error while sending score: {e}")
        return False


if __name__ == "__main__":
    os.environ["OPS_BOARD_URL"] = "http://119.3.152.42:3000/api/evaluation"
    send_skill_scores(
        {
            "linux-kernel-troubleshooting": 3.8,
            "linux-kernel-troubleshooting-optimized-20260130-121913": 5.0,
            "euleros-docker-hang": 4.60,
            "euleros-docker-hang-optimized-20260130-123321": 4.80
        }
    )
