"""
给定 URL，通过 Agent 抓取网页内容并转换为 Markdown。
复用 guides_extractor 的 fetch_guide_page 与 agent 模式；
通过 is_valid 区分正常内容与安全拦截/无有效内容。
"""

from __future__ import annotations

from typing import Dict, Any

from pydantic import BaseModel, Field

from langchain.agents import create_agent
from langchain.agents.structured_output import ToolStrategy
from langfuse import observe

from common import get_llm

from guides_extractor import fetch_guide_page


class HtmlExtractResult(BaseModel):
    """Agent 返回的结构化结果：能否正常获取内容 + Markdown + 技能名称"""

    is_valid: bool = Field(
        description="true 表示能正常获取到 URL 网页内容；false 表示存在安全拦截或没有抓取到有效内容"
    )
    markdown: str = Field(
        default="",
        description="当 is_valid=true 时为结构化的 Markdown 内容；否则为空字符串",
    )
    skill_name: str = Field(
        default="",
        description="从网页内容中提取的技能名称，如果无法提取则为空字符串",
    )


def create_html_extractor_agent():
    """
    创建 HTML 抓取 Agent：
    - 工具：fetch_guide_page（复用 guides_extractor）
    - 职责：根据 URL 抓取内容，判断是否有效，有效则输出 Markdown。

    Returns:
        agent: 可通过 agent.ainvoke(...) 调用的 CompiledGraph
    """
    system_prompt = """你是一个网页内容抓取助手。请使用工具 fetch_guide_page 根据给定 URL 抓取页面内容，并完成：

1. 判断抓取结果是否有效：
   - is_valid=true：能正常获取到网页正文，且为有效内容（非安全拦截、非验证页、非空白）。
   - is_valid=false：下列任一情况：
     * 抓取失败（工具返回「抓取失败」等）
     * 存在安全拦截：如人机验证、验证码、Cloudflare 挑战、Access denied、请完成验证等
     * 页面内容为空、非 HTML、或未抓取到任何有效正文

2. 提取技能名称（skill_name）：
   - 从网页标题、正文内容中识别并提取技能名称（如技术栈名称、工具名称、服务名称等）
   - 技能名称必须使用英文，单词之间用连字符（-）分隔，例如：kubernetes、docker-compose、aws-ec2、python-web-scraping
   - 技能名称应该是简洁、准确的，通常是一个名词或名词短语
   - 如果无法从内容中提取到明确的技能名称，则 skill_name 为空字符串

3. 输出规则：
   - 仅当 is_valid=true 时，将抓取到的内容转换为 Markdown 格式输出到 markdown 字段。
   - 重要：只做格式化转换，不要总结、不要概述、不要删减内容。保持原始内容的完整性和准确性。
   - 格式化要求：标题用 #，段落保持原样，列表保持原样，代码块用 ```，表格保持原样等。
   - 当 is_valid=false 时，markdown 和 skill_name 必须为空字符串。"""

    agent = create_agent(
        model=get_llm(),
        tools=[fetch_guide_page],
        system_prompt=system_prompt,
        response_format=ToolStrategy(HtmlExtractResult),
    )
    return agent


@observe
async def run_html_extractor(
    url: str,
    callback_config: Dict[str, Any] | None = None,
) -> Dict[str, str]:
    """
    给定 URL，通过 Agent 抓取内容并转为 Markdown，同时提取技能名称。

    Args:
        url: 要抓取的网页地址
        callback_config: 可选的 callback 配置（含 callbacks、configurable、metadata 等）

    Returns:
        Dict[str, str]: 包含以下字段的字典：
            - "markdown": 如果能够正常获取内容，返回 Markdown 格式的文本；否则返回空字符串
            - "skill_name": 从网页内容中提取的技能名称，如果无法提取则为空字符串
    """
    url = (url or "").strip()
    if not url:
        return {"markdown": "", "skill_name": ""}

    agent = create_html_extractor_agent()
    user_msg = f"请抓取以下 URL 的内容，判断是否有效、提取技能名称，并输出 Markdown：\n{url}"

    resp = await agent.ainvoke(
        {"messages": [{"role": "user", "content": user_msg}]},
        config=callback_config,
    )

    structured = resp.get("structured_response")
    if not isinstance(structured, HtmlExtractResult):
        return {"markdown": "", "skill_name": ""}

    # 如果 is_valid 为 true，返回 markdown 和 skill_name；否则返回空字符串
    if structured.is_valid:
        return {
            "markdown": structured.markdown.strip(),
            "skill_name": (structured.skill_name or "").strip(),
        }
    else:
        return {"markdown": "", "skill_name": ""}
