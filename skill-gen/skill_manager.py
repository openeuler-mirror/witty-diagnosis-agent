#!/usr/bin/env python3
"""
Skill 管理模块

列出 skill 列表或统计 keyword 数量，并在控制台以 rich 表格展示。
"""
from __future__ import annotations

import os
import re
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Tuple

import yaml
from rich.console import Console
from rich.table import Table


class SkillManager:
    """
    仅管理 custom skills（CUSTOM_SKILL_PATHS），统计 keyword -> skill 数量，并以 rich 表格输出。
    """

    def __init__(self) -> None:
        self._console = Console()

    def _parse_keywords_from_skill_md(self, skill_md_path: Path) -> List[str]:
        """从 SKILL.md 的 YAML frontmatter 中解析 metadata.keywords。"""
        try:
            text = skill_md_path.read_text(encoding="utf-8")
        except Exception:
            return []

        match = re.match(r"^---\r?\n(.*?)\r?\n---", text, re.DOTALL)
        if not match:
            return []

        try:
            meta = yaml.safe_load(match.group(1))
        except Exception:
            return []

        if not isinstance(meta, dict):
            return []

        md = meta.get("metadata")
        if not isinstance(md, dict):
            return []

        kw = md.get("keywords")
        if not isinstance(kw, list):
            return []

        return [str(x).strip() for x in kw if x is not None and str(x).strip()]

    def _collect_skills(self, root: Path | None) -> List[Tuple[str, List[str]]]:
        """扫描 root 下所有包含 SKILL.md 的子目录，返回 [(skill_name, keywords), ...]。"""
        result: List[Tuple[str, List[str]]] = []
        if root is None or not root.is_dir():
            return result

        for d in root.iterdir():
            if not d.is_dir():
                continue
            skill_md = d / "SKILL.md"
            if not skill_md.is_file():
                continue
            keywords = self._parse_keywords_from_skill_md(skill_md)
            result.append((d.name, keywords))
        return result

    def _keyword_counts(self, items: List[Tuple[str, List[str]]]) -> Dict[str, int]:
        """统计每个 keyword 对应的 skill 数量。"""
        counts: Dict[str, int] = defaultdict(int)
        for _name, kws in items:
            seen: set[str] = set()
            for k in kws:
                if k and k not in seen:
                    seen.add(k)
                    counts[k] += 1
        return dict(counts)

    def _print_section(self, title: str, total: int, counts: Dict[str, int]) -> None:
        """输出一个统计区块：标题、总数量、关键词数量、关键词矩阵表格（rich）。"""
        self._console.print(f"\n[bold cyan]{title}[/bold cyan]")
        self._console.print(f"总数量: [bold]{total}[/bold]")
        if not counts:
            self._console.print("  （无关键词统计）")
            return
        self._console.print(f"关键词数量: [bold]{len(counts)}[/bold]")
        
        # 矩阵显示：每行显示多个关键词，默认4列
        columns_per_row = 4
        sorted_keywords = sorted(counts.keys(), key=lambda k: (-counts[k], k))
        
        # 将关键词列表分成多行
        num_keywords = len(sorted_keywords)
        num_rows = (num_keywords + columns_per_row - 1) // columns_per_row
        
        # 创建表格，每列显示一个关键词
        table = Table(show_header=False, box=None, padding=(0, 2))
        for col_idx in range(columns_per_row):
            table.add_column(justify="left", style="dim", no_wrap=False)
        
        # 填充表格行
        for row_idx in range(num_rows):
            row_data = []
            for col_idx in range(columns_per_row):
                idx = row_idx * columns_per_row + col_idx
                if idx < num_keywords:
                    kw = sorted_keywords[idx]
                    count = counts[kw]
                    # 格式：关键词 (数量)
                    row_data.append(f"{kw} ({count})")
                else:
                    row_data.append("")
            table.add_row(*row_data)
        
        self._console.print(table)

    def list_skills(self) -> None:
        """
        仅列出 custom skills（CUSTOM_SKILL_PATHS 目录下），每行：index, skill-name, keywords。
        """
        # 读取环境变量并区分三种情况：
        # 1) 未配置 / 为空
        # 2) 已配置但路径不存在或不是目录
        # 3) 已配置且为有效目录
        raw = os.getenv("CUSTOM_SKILL_PATHS", "").strip()
        custom_dir: Path | None = None

        if not raw:
            self._console.print("\n[bold]Custom Skill 列表[/bold]")
            self._console.print(
                "[yellow]未检测到 custom skill。[/yellow] "
                "请设置环境变量 [bold]CUSTOM_SKILL_PATHS[/bold] 指向 custom skills 根目录，"
                "例如在 skill-gen 目录下的 .env 中配置：\n"
                "  CUSTOM_SKILL_PATHS=/path/to/custom_skills"
            )
            return

        custom_dir = Path(raw)
        if not custom_dir.exists() or not custom_dir.is_dir():
            self._console.print("\n[bold]Custom Skill 列表[/bold]")
            self._console.print(
                "[yellow]未检测到 custom skill。[/yellow] 环境变量 "
                "[bold]CUSTOM_SKILL_PATHS[/bold] 当前值为：\n"
                f"  [dim]{custom_dir}[/dim]\n"
                "但该路径不存在或不是目录，请检查路径是否正确。"
            )
            return

        custom_skills = self._collect_skills(custom_dir)

        self._console.print("\n[bold]Custom Skill 列表[/bold]")
        if custom_dir:
            self._console.print(f"目录: [dim]{custom_dir}[/dim]")
        self._console.print(f"总数量: [bold]{len(custom_skills)}[/bold]\n")
        if not custom_skills:
            self._console.print("  当前目录下暂无 skill（需包含 SKILL.md 的子目录）。")
            return

        table = Table(show_header=True, header_style="bold")
        table.add_column("序号", justify="right", style="dim")
        table.add_column("Skill Name", style="dim")
        table.add_column("Keywords", style="dim", no_wrap=False)
        for idx, (name, keywords) in enumerate(custom_skills, start=1):
            kw_str = ", ".join(keywords) if keywords else ""
            table.add_row(str(idx), name, kw_str)
        self._console.print(table)
        self._console.print()

    def run_stats(self) -> None:
        """
        仅针对 custom_skills，统计 keyword -> skill 数量，在控制台打印表格。
        """
        raw = os.getenv("CUSTOM_SKILL_PATHS", "").strip()
        custom_dir: Path | None = None

        self._console.print("\n[bold]Custom Skill 关键词统计[/bold]")

        if not raw:
            self._console.print(
                "[yellow]未检测到 custom skill。[/yellow] "
                "请设置环境变量 [bold]CUSTOM_SKILL_PATHS[/bold] 指向 custom skills 根目录，"
                "例如在 skill-gen 目录下的 .env 中配置：\n"
                "  CUSTOM_SKILL_PATHS=/path/to/custom_skills"
            )
            self._console.print()
            return

        custom_dir = Path(raw)
        if not custom_dir.exists() or not custom_dir.is_dir():
            self._console.print(
                "[yellow]未检测到 custom skill。[/yellow] 环境变量 "
                "[bold]CUSTOM_SKILL_PATHS[/bold] 当前值为：\n"
                f"  [dim]{custom_dir}[/dim]\n"
                "但该路径不存在或不是目录，请检查路径是否正确。"
            )
            self._console.print()
            return

        custom_skills = self._collect_skills(custom_dir)
        custom_counts = self._keyword_counts(custom_skills)

        if custom_dir:
            self._console.print(f"目录: [dim]{custom_dir}[/dim]")

        self._print_section("Custom Skills", len(custom_skills), custom_counts)
        self._console.print()


def run_skill_stats() -> None:
    """
    仅针对 custom skills 执行关键词统计输出（--list-keywords / -lk）。
    """
    SkillManager().run_stats()


def run_list_skills() -> None:
    """
    仅列出 custom skills，每行 index, skill-name, keywords（--list / -l）。
    """
    SkillManager().list_skills()
