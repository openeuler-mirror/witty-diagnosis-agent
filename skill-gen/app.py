import argparse
import os
from pathlib import Path

from rich.prompt import Prompt
from dotenv import load_dotenv

load_dotenv(override=True)
from skill_generation import run_skill_generation
from skill_manager import run_list_skills, run_skill_stats


# 工作目录：以当前文件所在目录作为 skill workspace 根目录
WORKSPACE_DIR = Path(__file__).resolve().parent


def main() -> None:
    """
    使用示例：
      - 生成单个 Skill：
          python app.py --input path/to/doc.pdf --output /path/to/skills --skill-name my-skill
      - 基于 JSON/目录批量生成：
          python app.py --input batch_config.json --concurrency 5
      - 列出所有 skills：
          python app.py --list
      - 统计关键词矩阵：
          python app.py --list-keywords
    """
    parser = argparse.ArgumentParser(
        description="基于文档的 Claude Skill 生成工具"
    )

    parser.add_argument(
        "--input",
        type=str,
        required=False,
        help="输入路径：单个文档(PDF/TXT/Markdown/URL)、JSON 配置文件或目录。",
    )
    parser.add_argument(
        "--list",
        "-l",
        action="store_true",
        dest="list_skills",
        help="列出所有 skills：索引、名称、关键词。",
    )
    parser.add_argument(
        "--list-keywords",
        "-lk",
        action="store_true",
        dest="list_keywords",
        help="统计关键词在各 skill 中的分布（矩阵形式）。",
    )
    parser.add_argument(
        "--output",
        type=str,
        default=os.getenv("CUSTOM_SKILL_PATHS") or None,
        help="生成的 skills 输出目录（默认读取环境变量 CUSTOM_SKILL_PATHS）。",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=3,
        help="批量生成时的并发数（默认：3）。",
    )
    parser.add_argument(
        "--skill-name",
        type=str,
        help="单文档模式下的 skill 名称；不提供则自动生成或交互确认。",
    )

    args = parser.parse_args()

    # 为 DeepSeek 适配器等组件提供模板查找根路径
    os.environ.setdefault("SKILL_WORKSPACE_DIR", str(WORKSPACE_DIR))

    if args.list_skills:
        run_list_skills()
        return

    if args.list_keywords:
        run_skill_stats()
        return

    input_path = args.input
    if not input_path:
        input_path = Prompt.ask(
            "[bold cyan]请输入输入路径[/bold cyan]（单个文档/JSON 配置/目录或 URL）"
        ).strip()
        if not input_path:
            parser.error("未提供输入路径，已退出。")

    run_skill_generation(
        input_path=input_path,
        output_path=args.output,
        concurrency=args.concurrency,
        skill_name=args.skill_name,
    )


if __name__ == "__main__":
    main()

