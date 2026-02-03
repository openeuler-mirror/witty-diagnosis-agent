#!/usr/bin/env python3
"""
Main entry point for skill optimization.
"""

import os
import sys
import shutil
import datetime
import json
import argparse
from pathlib import Path
from typing import Optional

# Add project root to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import dotenv
from gepa.strategies.instruction_proposal import InstructionProposalSignature

from optimization.constants import ENV_FILE
from optimization.proposer import SKILL_OPTIMIZATION_PROMPT
from optimization.utils import (
    get_skill_name_from_md,
    save_optimization_history,
    send_skill_scores,
    update_skill_name_in_md,
)
from optimization.adapter import load_dataset, run_gepa

# Import evaluation tool for report generation
# Ensure evaluation dependencies are met
try:
    from evaluation.evaluate_skill import call_deepseek_api
except ImportError:
    call_deepseek_api = None
    print(
        "Warning: Could not import call_deepseek_api from evaluation.evaluate_skill. Comparison reports will be skipped."
    )

# Load environment variables
dotenv.load_dotenv(override=True, dotenv_path=ENV_FILE)

import concurrent.futures

import re

# Set default prompt template for instruction proposal
InstructionProposalSignature.default_prompt_template = SKILL_OPTIMIZATION_PROMPT

PROMPT_COMPARISON_REPORT = """
You are an expert QA reviewer for AI Agent Skills.
Your task is to analyze the optimization results of a Skill and generate a "Change Report".

Below are the details of the optimization:
{content}

Please generate a concise **Optimization Comparison Report** in Markdown format that includes:
1. **Score Comparison**: Highlight the improvement from Original to Optimized score.
2. **Key Changes**: Summarize the main differences between the two versions.
3. **Improvement Analysis**: Explain *why* the optimized version is better (e.g., improved clarity, better edge case handling, more robust logic).
4. **Conclusion**: Brief final verdict.

Output ONLY the Markdown report.
"""


def generate_and_save_report(
    skill_name: str,
    original_content: str,
    optimized_content: str,
    original_score: float,
    optimized_score: float,
    output_dir: Path,
    timestamp: str,
):
    if not call_deepseek_api:
        return

    print(f"Generating comparison report for {skill_name}...")

    # Construct the content for the LLM
    content_payload = f"""
Skill Name: {skill_name}
Original Score: {original_score}
Optimized Score: {optimized_score}

=== ORIGINAL VERSION ===
{original_content}

=== OPTIMIZED VERSION ===
{optimized_content}
"""

    try:
        response = call_deepseek_api(PROMPT_COMPARISON_REPORT, content_payload)

        report_text = ""
        if response and "choices" in response:
            report_text = response["choices"][0]["message"]["content"]

        if report_text:
            # Clean up markdown code blocks if present
            if report_text.strip().startswith("```markdown"):
                report_text = report_text.strip()[11:]
            if report_text.strip().endswith("```"):
                report_text = report_text.strip()[:-3]

            report_filename = f"report_{skill_name}_{timestamp}.md"
            report_path = output_dir / report_filename

            with open(report_path, "w", encoding="utf-8") as f:
                f.write(report_text)

            print(f"Comparison report saved to: {report_path}")
        else:
            print("Failed to generate report: Empty response from LLM.")

    except Exception as e:
        print(f"Error generating comparison report: {e}")


def optimize_single_skill(
    target_skill_file: Path, output_dir: Optional[Path] = None
) -> dict:
    print(f"\n>>> Starting optimization for: {target_skill_file}")

    with open(target_skill_file, "r", encoding="utf-8") as f:
        skill_content = f.read()

    skill_name = get_skill_name_from_md(skill_content)
    print(f"Extracted skill name: {skill_name}")

    # Get configuration from env
    examples_count = int(os.environ.get("GEPA_EXAMPLES_COUNT", "1"))
    perfect_score = float(os.environ.get("GEPA_PERFECT_SCORE", "5.0"))
    verbose = os.environ.get("GEPA_VERBOSE", "False").lower() == "true"
    max_metric_calls = int(os.environ.get("GEPA_MAX_METRIC_CALLS", "10"))

    try:
        dummy_dataset = load_dataset(skill_name, num_examples=examples_count)
    except Exception as e:
        error_msg = f"Skipping {skill_name}: Failed to load dataset. Error: {e}"
        print(error_msg)
        return {
            "skill_name": skill_name,
            "status": "Failed",
            "error": error_msg,
            "original_score": "N/A",
            "optimized_score": "N/A",
        }

    # Use the actual content as seed
    seed_candidate = {"skill_md": skill_content}

    try:
        result, history = run_gepa(
            trainset=dummy_dataset,
            valset=dummy_dataset,
            seed_candidate=seed_candidate,
            max_metric_calls=max_metric_calls,
            perfect_score=perfect_score,
            verbose=verbose,
        )
    except Exception as e:
        error_msg = f"Optimization failed for {skill_name}: {e}"
        print(error_msg)
        import traceback

        traceback.print_exc()
        return {
            "skill_name": skill_name,
            "status": "Failed",
            "error": error_msg,
            "original_score": "N/A",
            "optimized_score": "N/A",
        }

    # Save history to JSON
    save_optimization_history(
        history, target_skill_file, output_dir=output_dir, skill_name=skill_name
    )

    # Calculate scores
    original_score = "N/A"
    optimized_score = 0.0

    # Try to find original score from history (usually round 0)
    if history:
        seed_entry = next((h for h in history if h.get("round") == 0), None)
        if seed_entry:
            original_score = seed_entry.get("average_score", "N/A")
        else:
            # Fallback: assume first entry
            original_score = history[0].get("average_score", "N/A")

    # Extract optimized skill content and score from result
    optimized_content = ""

    # 1. Try result object attributes (GEPA standard return)
    if hasattr(result, "candidate") and isinstance(result.candidate, dict):
        optimized_content = (
            result.candidate.get("skill_md")
            or result.candidate.get("instruction")
            or ""
        )
        # Try to get score from result
        if hasattr(result, "val_aggregate_scores") and hasattr(result, "best_idx"):
            try:
                # GEPA scores are usually 0-1
                norm_score = result.val_aggregate_scores[result.best_idx]
                optimized_score = norm_score * 5.0
            except (IndexError, TypeError):
                pass

    # 2. Try result as Dictionary (Legacy/Fallback)
    if not optimized_content and isinstance(result, dict):
        optimized_content = result.get("skill_md") or result.get("instruction") or ""
        # If result is a dict, it might not have score info directly unless added by wrapper

    # 3. Fallback to history if content missing
    if not optimized_content:
        print(
            "Warning: Could not extract optimized content from result object. Falling back to history."
        )
        if history:
            # Prefer the one with highest score
            best_entry = max(history, key=lambda x: x.get("average_score", 0))
            optimized_content = best_entry.get("skill_content", "")
            optimized_score = best_entry.get("average_score", 0.0)
            print(
                f"Selected best skill from Round {best_entry.get('round')} with Score {best_entry.get('average_score')}"
            )

    # Ensure optimized_score is set if we have content but score was missed from result object
    if optimized_content and optimized_score == 0.0:
        # Try to find matching score in history
        matching_entry = next(
            (h for h in history if h.get("skill_content") == optimized_content), None
        )
        if matching_entry:
            optimized_score = matching_entry.get("average_score", 0.0)
        elif history:
            # Last resort fallback
            best_entry = max(history, key=lambda x: x.get("average_score", 0))
            optimized_score = best_entry.get("average_score", 0.0)

    # Save results
    if optimized_content and optimized_content != skill_content:
        print("Optimization successful. Saving results...")

        # 生成时间戳，用于版本控制
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

        # 移除已有的后缀（如果存在），避免重复追加
        # 匹配格式：[_-]optimized[_-]YYYYMMDD[_-]HHMMSS
        base_skill_name = re.sub(r"[_-]optimized[_-]\d{8}[_-]\d{6}$", "", skill_name)

        # 更新 Skill 名称，加上时间戳后缀，避免名称冲突
        new_skill_name = f"{base_skill_name}-optimized-{timestamp}"

        # 保存原始的 optimized content 用于报告（未修改名称前）
        optimized_content_raw = optimized_content

        optimized_content = update_skill_name_in_md(optimized_content, new_skill_name)
        print(f"Updated skill name to: {new_skill_name}")

        # 备份原始文件，文件名格式：legacy_{skill_name}_{timestamp}.md
        backup_filename = f"legacy_{base_skill_name}_{timestamp}.md"
        if output_dir:
            if not output_dir.exists():
                output_dir.mkdir(parents=True, exist_ok=True)
            backup_path = output_dir / backup_filename
            report_dir = output_dir
        else:
            backup_path = target_skill_file.with_name(backup_filename)
            report_dir = target_skill_file.parent

        shutil.copy2(target_skill_file, backup_path)
        print(f"Backed up original skill to: {backup_path}")

        # 将优化后的内容写入原文件
        with open(target_skill_file, "w", encoding="utf-8") as f:
            f.write(optimized_content)
        print(f"Updated original skill file: {target_skill_file}")

        # === 生成对比报告 ===
        if call_deepseek_api:
            try:
                # 转换分数为 float 以便显示
                orig_score_val = (
                    float(original_score)
                    if isinstance(original_score, (int, float, str))
                    and str(original_score).replace(".", "", 1).isdigit()
                    else 0.0
                )
                opt_score_val = (
                    float(optimized_score)
                    if isinstance(optimized_score, (int, float))
                    else 0.0
                )

                generate_and_save_report(
                    skill_name=base_skill_name,
                    original_content=skill_content,
                    optimized_content=optimized_content_raw,  # 使用未重命名的内容进行对比分析
                    original_score=orig_score_val,
                    optimized_score=opt_score_val,
                    output_dir=report_dir,
                    timestamp=timestamp,
                )
            except Exception as e:
                print(f"Failed to initiate report generation: {e}")

    else:
        if optimized_content == skill_content:
            print(
                "Optimization completed but no improvement was found (content unchanged)."
            )
        else:
            print(
                "No improvement found or optimization failed to return valid content."
            )

    # Print summary and send score to ops board
    if history or optimized_content:
        print("\n=== Optimization Summary ===")
        print(f"Best Score: {optimized_score:.2f} / 5.0")

        # Find round number for optimized content
        best_round = "N/A"
        if history:
            # Try to match content exactly
            match = next(
                (h for h in history if h.get("skill_content") == optimized_content),
                None,
            )
            if match:
                best_round = match.get("round")

        print(f"Best Round: {best_round}")

        # Try to print GEPA best result raw score if available
        if hasattr(result, "val_aggregate_scores") and hasattr(result, "best_idx"):
            try:
                raw_score = result.val_aggregate_scores[result.best_idx]
                print(f"GEPA Best Candidate Score (Raw): {raw_score}")
            except (IndexError, TypeError):
                pass

    return {
        "skill_name": skill_name,
        "status": "Success",
        "original_score": original_score,
        "optimized_score": optimized_score,
        "error": None,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Optimize OpsAgent skills using GEPA/LLM."
    )
    parser.add_argument(
        "--input",
        "-i",
        type=str,
        help="Path to the skill file or directory to optimize. Overrides OPT_SKILLS_DIR env var.",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        help="Directory to save optimization results and backups. Overrides OPT_OUTPUT_DIR env var.",
    )
    args = parser.parse_args()

    # Get OPT_SKILLS_DIR from args or env or use default
    if args.input:
        skills_path_str = args.input
        print(f"Using input path from CLI args: {skills_path_str}")
    else:
        skills_path_str = os.environ.get("OPT_SKILLS_DIR", "skills")
        print(f"Using input path from environment (or default): {skills_path_str}")

    skills_path = Path(skills_path_str).expanduser().resolve()

    # Get OPT_OUTPUT_DIR from args or env
    if args.output:
        opt_output_dir_str = args.output
        print(f"Using output directory from CLI args: {opt_output_dir_str}")
    else:
        opt_output_dir_str = os.environ.get("OPT_OUTPUT_DIR")
        if opt_output_dir_str:
            print(f"Using output directory from environment: {opt_output_dir_str}")

    opt_output_dir = (
        Path(opt_output_dir_str).expanduser().resolve() if opt_output_dir_str else None
    )

    if opt_output_dir:
        print(f"Final output directory resolved to: {opt_output_dir}")
        if not opt_output_dir.exists():
            opt_output_dir.mkdir(parents=True, exist_ok=True)

    if not skills_path.exists():
        print(f"Error: Skills directory/file not found at {skills_path}")
        sys.exit(1)

    skill_files = []

    # 1. If path is a file, check if it's a SKILL.md
    if skills_path.is_file() and skills_path.name.lower() == "skill.md":
        skill_files.append(skills_path)

    # 2. If path is a directory
    elif skills_path.is_dir():
        # Check if the directory itself is a skill directory (contains SKILL.md)
        # Using glob to find SKILL.md case-insensitively if needed, but here we assume SKILL.md or SKILL.MD
        # The user reference uses [Ss][Kk][Ii][Ll][Ll].[Mm][Dd] glob pattern.
        direct_skill = next(skills_path.glob("[Ss][Kk][Ii][Ll][Ll].[Mm][Dd]"), None)
        if direct_skill:
            skill_files.append(direct_skill)
        else:
            # Check immediate subdirectories for SKILL.md
            for sub_dir in skills_path.iterdir():
                if sub_dir.is_dir():
                    sub_skill = next(
                        sub_dir.glob("[Ss][Kk][Ii][Ll][Ll].[Mm][Dd]"), None
                    )
                    if sub_skill:
                        skill_files.append(sub_skill)

    if not skill_files:
        print(
            f"Error: No SKILL.md found in {skills_path} or its immediate subdirectories."
        )
        sys.exit(1)

    print(f"Found {len(skill_files)} skill(s) to optimize.")

    # Get max workers from env or default to 4
    max_workers_str = os.environ.get("OPTIMIZATION_MAX_WORKERS", "4")
    try:
        max_workers = int(max_workers_str)
    except ValueError:
        print("OPTIMIZATION_MAX_WORKERS is invalid, using default 4")
        max_workers = 4

    summary_results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(optimize_single_skill, skill_file, opt_output_dir)
            for skill_file in skill_files
        ]

        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                if result:
                    summary_results.append(result)
            except Exception as e:
                print(f"Critical error in optimization task: {e}")

    # Print summary table
    print("\n" + "=" * 80)
    print(
        f"{'Skill Name':<30} | {'Original Score':<15} | {'Optimized Score':<15} | {'Status':<10}"
    )
    print("-" * 80)

    for res in sorted(summary_results, key=lambda x: x.get("skill_name", "")):
        skill_name = res.get("skill_name", "Unknown")
        # Truncate skill name if too long
        if len(skill_name) > 28:
            skill_name = skill_name[:25] + "..."

        orig = res.get("original_score", "N/A")
        opt = res.get("optimized_score", "N/A")
        status = res.get("status", "Unknown")

        # Format scores if they are floats
        if isinstance(orig, float):
            orig = f"{orig:.2f}"
        if isinstance(opt, float):
            opt = f"{opt:.2f}"

        print(f"{skill_name:<30} | {orig:<15} | {opt:<15} | {status:<10}")

    print("=" * 80 + "\n")

    # Collect and send scores to ops board
    scores_to_send = {}
    for res in summary_results:
        skill_name = res.get("skill_name")
        optimized_score = res.get("optimized_score")

        if skill_name and isinstance(optimized_score, (int, float)):
            scores_to_send[skill_name] = float(optimized_score)

    if scores_to_send:
        print("\nSending all skill scores to ops board...")
        success = send_skill_scores(scores_to_send)
        if not success:
            print("Failed to send scores. Pending scores:")
            print(json.dumps(scores_to_send, indent=2, ensure_ascii=False))
    else:
        print("\nNo valid scores to send.")


if __name__ == "__main__":
    print("--- Start optimization process.")
    start_time = datetime.datetime.now()
    print(start_time.strftime("%Y-%m-%d %H:%M:%S"))
    main()
    end_time = datetime.datetime.now()
    print(end_time.strftime("%Y-%m-%d %H:%M:%S"))
    duration = end_time - start_time
    print(f"Total duration: {duration}")
    print("--- End optimization process.")
