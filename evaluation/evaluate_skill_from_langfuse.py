import os
import logging
from typing import Any, Dict, List, Tuple
import dotenv
from langfuse import Langfuse
from constants import ENV_FILE

from evaluation.evaluate_skill import (
    call_deepseek_api,
    parse_evaluation_response,
    compute_evaluation_scores,
    build_evaluation_report,
    save_report,
)
from evaluation.prompts import PROMPT_SKILL_META, PROMPT_CODE_QUALITY
from evaluation.utils import check_environment_variables


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


dotenv.load_dotenv(override=True, dotenv_path=ENV_FILE)
check_environment_variables(
    [
        "DEEPSEEK_API_KEY",
        "LANGFUSE_PUBLIC_KEY",
        "LANGFUSE_SECRET_KEY",
        "EVALUATION_SKILL_PATH",
        "EVALUATION_LANGFUSE_DATASET_NAME",
    ]
)
langfuse = Langfuse()


def _join_dict_content(d: Dict[str, str]) -> str:
    parts: List[str] = []
    for path, content in d.items():
        parts.append(f"--- 文件: {path} ---\n{content}\n")
    return "".join(parts)


def _evaluate_item_input(
    input_payload: Dict[str, Any],
) -> Tuple[List[Dict[str, Any]], str, List[Dict[str, Any]], str]:
    meta_prompt = PROMPT_SKILL_META
    code_prompt = PROMPT_CODE_QUALITY

    # 评估技能描述
    skill_md = input_payload.get("skill_md") or ""
    meta_response = call_deepseek_api(meta_prompt, skill_md)
    meta_results, meta_comment = parse_evaluation_response(meta_response)

    # 评估技能代码
    references = (
        input_payload.get("references") or input_payload.get("reference_preview") or {}
    )
    scripts = input_payload.get("scripts") or {}
    combined_code_content = _join_dict_content(references) + _join_dict_content(scripts)
    code_response = call_deepseek_api(code_prompt, combined_code_content)
    code_results, code_comment = parse_evaluation_response(code_response)

    return meta_results, meta_comment, code_results, code_comment


def evaluate_dataset_items(dataset_name: str, limit: int | None = None) -> None:
    dataset = langfuse.get_dataset(dataset_name)
    items = dataset.items
    if limit is not None:
        items = items[:limit]
    logging.info("从 Langfuse 数据集 %s 读取到 %d 条 items", dataset_name, len(items))
    for item in items:
        input_payload = getattr(item, "input", {}) or {}
        if not isinstance(input_payload, dict):
            logging.warning("跳过 item %s: input 不是 dict", getattr(item, "id", None))
            continue
        skill_name = input_payload.get("skill_name") or getattr(
            item, "id", "unknown_skill"
        )
        meta_results, meta_comment, code_results, code_comment = _evaluate_item_input(
            input_payload
        )
        all_results = meta_results + code_results

        average_score, sorted_results = compute_evaluation_scores(all_results)
        report_content = build_evaluation_report(
            skill_name=skill_name,
            average_score=average_score,
            meta_comment=meta_comment,
            code_comment=code_comment,
            sorted_results=sorted_results,
        )

        # 保存到本地
        save_report(skill_name, report_content)

        # 将分数保存到langfuse
        with item.run(run_name="evaluation_run") as root_span:
            for dim_res in all_results:
                name = dim_res.get("dimension") or "unknown_dim"
                score = dim_res.get("score") or 0
                comment = dim_res.get("justification") or ""
                root_span.score(
                    name=name,
                    value=score,
                    comment=comment,
                    data_type="NUMERIC",
                )

            root_span.score(
                name="average_score",
                value=average_score,
                comment=f"[ Skill评估总结 ]: {meta_comment}\n[ 代码质量评估总结 ]: {code_comment}",
                data_type="NUMERIC",
            )

            output = f"evaluation results for {skill_name}"
            output += "\n" + report_content
            root_span.update(input=input_payload, output=output)

            langfuse.flush()


def main() -> None:
    dataset_name = os.environ.get("EVALUATION_LANGFUSE_DATASET_NAME")
    limit_str = os.environ.get("EVALUATION_LANGFUSE_DATASET_LIMIT")
    if limit_str is None or limit_str == "":
        final_limit = None
    else:
        try:
            final_limit = int(limit_str)
        except ValueError:
            logging.warning("EVALUATION_LANGFUSE_DATASET_LIMIT 配置非整数，将忽略该值")
            final_limit = None

    evaluate_dataset_items(dataset_name, limit=final_limit)


if __name__ == "__main__":
    main()
