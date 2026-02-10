from typing import Optional
import dotenv
import os
import sys
import json
from pathlib import Path
import logging
from datetime import datetime
import concurrent.futures

from rich.console import Console
from rich.table import Table

from rich.console import Console
from rich.table import Table

from langchain_openai import ChatOpenAI

# Add project root to sys.path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from evaluation.constants import ENV_FILE
from evaluation.prompts import PROMPT_SKILL_META, PROMPT_CODE_QUALITY, DIMENSION_ORDER
from evaluation.utils import check_environment_variables, format_header

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)

dotenv.load_dotenv(override=True, dotenv_path=ENV_FILE)


def load_file_content(file_path: Path) -> str:
    """加载单个文件的内容，如果文件不存在则返回空字符串。"""
    if not file_path.is_file():
        logging.warning(f"文件未找到: {file_path}")
        return ""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        logging.error(f"读取文件时发生错误 {file_path}: {e}")
        return ""


def load_directory_content(dir_path: Path) -> str:
    """加载目录下所有文件的内容并合并。"""
    if not dir_path.is_dir():
        logging.warning(f"目录未找到: {dir_path}")
        return ""

    all_content = []
    for file_path in dir_path.rglob("*"):
        if file_path.is_file():
            logging.info(f"正在读取 reference 文件: {file_path.name}")
            content = load_file_content(file_path)
            all_content.append(f"--- 文件: {file_path.name} ---\n{content}\n")

    return "\n".join(all_content)


def call_deepseek_api(prompt: str, content: str) -> dict:
    """调用 DeepSeek API 获取评估结果，并带有重试逻辑。"""
    if not content.strip():
        logging.warning("评估内容为空，跳过 API 调用。")
        return None

    final_prompt = prompt.format(content=content)

    max_retries = 3

    llm = ChatOpenAI(
        model=os.getenv("DEEPSEEK_MODEL", "deepseek-chat"),
        base_url=os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com/"),
        api_key=os.getenv("DEEPSEEK_API_KEY"),
        max_retries=max_retries,
    )

    response = llm.invoke(final_prompt)
    content_str = getattr(response, "content", None)
    if not isinstance(content_str, str):
        content_str = str(response)
    return {"choices": [{"message": {"content": content_str}}]}


def parse_evaluation_response(response: dict) -> list:
    """解析 API 返回的 JSON 评估结果。"""
    if not response:
        return [], ""
    try:
        content_str = (
            response.get("choices", [{}])[0].get("message", {}).get("content", "{}")
        )

        # 清理 Markdown 代码块标识
        cleaned_content = content_str.strip()
        if cleaned_content.startswith("```"):
            # 去掉开头的 ```json 或 ```
            first_newline = cleaned_content.find("\n")
            if first_newline != -1:
                cleaned_content = cleaned_content[first_newline + 1 :]

            # 去掉结尾的 ```
            if cleaned_content.endswith("```"):
                cleaned_content = cleaned_content[:-3]

        evaluation_data = json.loads(cleaned_content.strip())
        detailed_evaluation = evaluation_data.get("detailed_evaluation", [])
        overall_comment = evaluation_data.get("overall_comment", "")
        return detailed_evaluation, overall_comment
    except (json.JSONDecodeError, IndexError, KeyError) as e:
        logging.error(f"解析评估响应时出错: {e}")
        logging.error(f"收到的原始响应内容: {content_str}")
        return [], ""


def compute_evaluation_scores(results: list) -> tuple[float, list]:
    valid_scores = []

    # 转换每个结果的分数为 float
    for item in results:
        score_val = item.get("score", 0)
        try:
            # 尝试转换为 float
            float_score = float(score_val)
            item["score"] = float_score  # 更新回原字典
            valid_scores.append(float_score)
        except (ValueError, TypeError):
            # 如果转换失败（例如是 "N/A" 或其他非数字），保持原样或设为 0，这里选择跳过计入总分
            pass

    total_score = sum(valid_scores)
    average_score = total_score / len(valid_scores) if valid_scores else 0

    sorted_results = sorted(
        results,
        key=lambda x: (
            DIMENSION_ORDER.index(x.get("dimension"))
            if x.get("dimension") in DIMENSION_ORDER
            else 99
        ),
    )
    return average_score, sorted_results


def build_evaluation_report(
    skill_name: str,
    average_score: float,
    meta_comment: str,
    code_comment: Optional[str],
    sorted_results: list,
) -> str:
    report_lines = []
    report_lines.append(format_header(f"Skill 综合评估报告: {skill_name}", width=60))
    report_lines.append(f"\n[ 最终平均分 ]: {average_score:.1f} / 5.0")
    report_lines.append(f"[ Skill评估总结 ]: {meta_comment}")
    if code_comment:
        report_lines.append(f"[ 代码质量评估总结 ]: {code_comment}")
    report_lines.append("\n--- 各维度详细评分 ---\n")
    for item in sorted_results:
        dimension = item.get("dimension", "未知维度")
        score = item.get("score", "N/A")
        justification = item.get("justification", "无理由")
        report_lines.append(f"  - {dimension}: {score}/5")
        report_lines.append(f"    理由: {justification}\n")
    return "\n".join(report_lines)


def get_score_style(score) -> str:
    """根据分数返回对应的颜色样式。"""
    try:
        val = float(score)
        if val < 3.0:
            return "red"
        elif val < 4.0:
            return "#ffa500"  # 3分段用橙色
        elif val < 5.0:
            return "cyan"  # 4分段用青色
        else:
            return "green"  # 5分用绿色
    except (ValueError, TypeError):
        return "black"


def print_and_save_summary_table(summary_data: list) -> None:
    """打印所有 Skill 的评估结果汇总表。"""
    console = Console(record=True)
    table = Table(
        title="SKILL EVALUATION SUMMARY", show_header=True, header_style="magenta"
    )

    table.add_column("Skill Name", style="dim")
    table.add_column("Total Score", justify="right")

    for dim in DIMENSION_ORDER:
        table.add_column(dim, justify="right")

    for item in summary_data:
        skill_name = item["skill_name"]

        # 处理总分
        avg_score = item["average_score"]
        total_score_str = f"{avg_score:.1f}"
        total_score_style = get_score_style(avg_score)
        total_score_cell = (
            f"[{total_score_style}]{total_score_str}[/{total_score_style}]"
        )

        row_cells = [skill_name, total_score_cell]

        # 处理各维度分数
        scores_map = item["dimension_scores"]
        for dim in DIMENSION_ORDER:
            score = scores_map.get(dim, "N/A")
            score_str = (
                f"{score:.1f}" if isinstance(score, (int, float)) else str(score)
            )
            score_style = get_score_style(score)
            row_cells.append(f"[{score_style}]{score_str}[/{score_style}]")

        table.add_row(*row_cells)

    console.print(table)

    # 保存到文件
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_dir_env = os.environ.get("EVALUATION_REPORT_DIR")
    if report_dir_env:
        report_dir = Path(report_dir_env)
    else:
        report_dir = Path(__file__).parent / "reports"

    report_path = report_dir / f"summary_{timestamp}.html"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    console.save_html(str(report_path))


def evaluate_skill_meta(skill_meta_content: str) -> tuple[list, str]:
    """评估技能元数据内容，返回评估结果和评论。"""
    meta_response = call_deepseek_api(PROMPT_SKILL_META, skill_meta_content)
    meta_results, meta_comment = parse_evaluation_response(meta_response)
    return meta_results, meta_comment


def evaluate_skill_code(reference_content: str, code_content: str) -> tuple[list, str]:
    """评估技能代码内容，返回评估结果和评论。"""
    code_response = call_deepseek_api(
        PROMPT_CODE_QUALITY, reference_content + code_content
    )
    code_results, code_comment = parse_evaluation_response(code_response)
    return code_results, code_comment


def generate_evaluation_result(skill_dir: Path) -> dict:
    """仅执行评估逻辑，返回包含所有评估数据和报告内容的字典。"""
    logging.info(f"--- 开始评估 Skill: {skill_dir.name} ---")

    if not skill_dir.is_dir():
        logging.error(f"错误: 提供的路径不是一个目录 -> {skill_dir}")
        return None

    # 1. 评估技能描述
    logging.info(f"[{skill_dir.name}] 阶段 1: 评估 Skill 元数据 (SKILL.md)")
    skill_md_path = next(skill_dir.glob("[Ss][Kk][Ii][Ll][Ll].[Mm][Dd]"), None)
    if not skill_md_path:
        logging.error(f"错误: 在 {skill_dir} 中未找到 SKILL.md 或 skill.md 文件。")
        return None

    skill_meta_content = load_file_content(skill_md_path)
    meta_results, meta_comment = evaluate_skill_meta(skill_meta_content)

    # 2. 评估技能代码
    logging.info(f"[{skill_dir.name}] 阶段 2: 评估代码质量 (references)")
    references_path = skill_dir / "references"
    scripts_path = skill_dir / "scripts"
    reference_content = load_directory_content(references_path)
    code_content = load_directory_content(scripts_path)
    code_results, code_comment = evaluate_skill_code(reference_content, code_content)

    # 3. 合并结果
    logging.info(f"[{skill_dir.name}] 阶段 3: 生成综合评估报告")
    all_results = meta_results + code_results

    average_score, sorted_results = compute_evaluation_scores(all_results)

    # 构造 dimension_scores 字典供汇总表使用
    dimension_scores = {
        item.get("dimension"): item.get("score")
        for item in sorted_results
        if item.get("dimension")
    }

    report_content = build_evaluation_report(
        skill_name=skill_dir.name,
        average_score=average_score,
        meta_comment=meta_comment,
        code_comment=code_comment,
        sorted_results=sorted_results,
    )

    return {
        "skill_name": skill_dir.name,
        "average_score": average_score,
        "detailed_results": sorted_results,
        "dimension_scores": dimension_scores,
        "meta_comment": meta_comment,
        "code_comment": code_comment,
        "report_content": report_content,
    }


def evaluate_single_skill(skill_dir: Path, save_report_to_file: bool = True) -> dict:
    """评估单个 Skill 目录并生成报告，返回摘要数据。"""
    result = generate_evaluation_result(skill_dir)
    if result and save_report_to_file:
        save_report(result["skill_name"], result["report_content"])
    return result


def save_report(skill_name: str, report_content: str, reports_dir: Path = None) -> None:
    """将评估报告保存到文件。"""
    if reports_dir is None or not reports_dir.exists():
        # 创建报告目录
        reports_dir_env = os.getenv("EVALUATION_REPORT_DIR")
        if reports_dir_env:
            reports_dir = Path(reports_dir_env)
        else:
            reports_dir = Path(__file__).parent / "reports"

    reports_dir.mkdir(exist_ok=True, parents=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_filename = f"{skill_name}_{timestamp}.txt"
    report_path = reports_dir / report_filename

    try:
        with open(report_path, "w", encoding="utf-8") as f:
            f.write(report_content)
        logging.info(f"评估报告已成功保存到: {report_path}")
    except IOError as e:
        logging.error(f"保存报告文件时出错: {e}")


def main():
    """主函数"""
    check_environment_variables(
        ["DEEPSEEK_API_KEY", "EVALUATION_SKILL_PATH", "EVALUATION_REPORT_DIR"]
    )

    skill_path_str = os.environ.get("EVALUATION_SKILL_PATH")
    skill_path = Path(skill_path_str).expanduser().resolve()

    if not skill_path.exists():
        logging.error(f"错误: 提供的路径不存在 -> {skill_path}")
        exit(1)

    skill_dirs_to_evaluate = []
    if (
        skill_path.is_dir()
        and next(skill_path.glob("[Ss][Kk][Ii][Ll][Ll].[Mm][Dd]"), None) is not None
    ):
        # 如果路径本身就是一个 Skill 目录
        skill_dirs_to_evaluate.append(skill_path)
    elif skill_path.is_dir():
        # 如果路径是一个包含多个 Skill 目录的父目录
        for sub_dir in skill_path.iterdir():
            if sub_dir.is_dir() and next(
                sub_dir.glob("[Ss][Kk][Ii][Ll][Ll].[Mm][Dd]"), None
            ):
                skill_dirs_to_evaluate.append(sub_dir)

    if not skill_dirs_to_evaluate:
        logging.warning(f"在路径 {skill_path} 下未找到任何有效的 Skill 目录。")
        return

    logging.info(f"找到 {len(skill_dirs_to_evaluate)} 个 Skill 待评估。")

    max_workers_str = os.environ.get("EVALUATION_MAX_WORKERS", "4")
    try:
        max_workers = int(max_workers_str)
    except ValueError:
        logging.warning("EVALUATION_MAX_WORKERS 配置非法，将使用默认值 4")
        max_workers = 4

    summary_results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(evaluate_single_skill, skill_dir)
            for skill_dir in skill_dirs_to_evaluate
        ]
        for future in concurrent.futures.as_completed(futures):
            try:
                result = future.result()
                if result:
                    summary_results.append(result)
            except Exception as e:
                logging.error(f"一个评估任务在执行过程中发生严重错误: {e}")

    # 打印并保存汇总表格
    if summary_results:
        # 按 skill_name 排序
        summary_results.sort(key=lambda x: x["skill_name"])
        print_and_save_summary_table(summary_results)
    else:
        logging.info("没有生成有效的评估结果。")


if __name__ == "__main__":
    main()
