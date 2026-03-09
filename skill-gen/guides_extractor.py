"""
根据 guides/index.json 中的链接信息，抓取对应网页的基础信息。
"""

from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
from pathlib import Path
from typing import List, Dict

import httpx
from bs4 import BeautifulSoup
from pydantic import BaseModel, Field

from langchain_core.tools import tool
from langchain.agents import create_agent
from langchain.agents.structured_output import ToolStrategy
from langfuse import observe

from common import get_llm


class GuideAnalysisResult(BaseModel):
    """Agent 返回的结构化结果模型"""
    is_valid: bool = Field(
        description="true 表示能正确获取到 URL 网页内容，且与用户操作指引相关；false 表示不能获取内容或不是操作指引"
    )
    markdown: str = Field(
        default="",
        description="如果是操作指引，这里是结构化的 Markdown 内容；否则为空字符串"
    )


def load_guides_index(index_path: str) -> List[Dict[str, str]]:
    """
    从 guides/index.json 读取 name/url 列表，并过滤相同网页地址。

    Args:
        index_path: index.json 路径

    Returns:
        列表，元素为 {"name": str, "url": str}，已去重（基于URL）
    """
    p = Path(index_path)
    if not p.exists():
        raise FileNotFoundError(f"guides index.json 不存在: {p}")

    with p.open("r", encoding="utf-8") as f:
        data = json.load(f)

    # 兼容将来可能的其他结构，这里只提取 name/url
    items: List[Dict[str, str]] = []
    seen_urls = set()  # 用于去重
    
    if isinstance(data, list):
        for item in data:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", "") or "")
            url = str(item.get("url", "") or "").strip()
            if not url:
                continue
            # 过滤相同URL
            if url not in seen_urls:
                seen_urls.add(url)
                items.append({"name": name, "url": url})
    else:
        # 如果以后改成 {"links": [...]} 之类，这里可以扩展
        links = data.get("links", []) if isinstance(data, dict) else []
        for item in links:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", "") or "")
            url = str(item.get("url", "") or "").strip()
            if not url:
                continue
            # 过滤相同URL
            if url not in seen_urls:
                seen_urls.add(url)
                items.append({"name": name, "url": url})

    return items


async def fetch_url_info(url: str, timeout: int = 10) -> Dict[str, str]:
    """
    抓取单个 URL 的网页信息（标题和完整正文内容）。

    返回字段：
    - url: 原始 URL
    - ok:  是否抓取成功（bool）
    - error: 错误信息（失败时）
    - title: 网页 <title> 文本
    - content: 完整的网页文本内容
    """
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/122.0.0.0 Safari/537.36"
        )
    }

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.get(url, headers=headers)
        resp.raise_for_status()
    except Exception as e:
        return {
            "url": url,
            "ok": False,
            "error": str(e),
            "title": "",
            "content": "",
        }

    content_type = resp.headers.get("Content-Type", "").lower()
    if "html" not in content_type:
        return {
            "url": url,
            "ok": True,
            "error": "",
            "title": "",
            "content": f"非 HTML 内容: {content_type}",
        }

    html = resp.text
    soup = BeautifulSoup(html, "html.parser")

    # 提取标题
    title = (soup.title.string.strip() if soup.title and soup.title.string else "").strip()

    # 直接提取所有文本内容，不做任何过滤
    full_text = soup.get_text(separator="\n", strip=True)

    return {
        "url": url,
        "ok": True,
        "error": "",
        "title": title,
        "content": full_text,
    }


@tool
async def fetch_guide_page(url: str) -> str:
    """
    网页爬取工具（异步）：根据给定 URL 抓取页面内容并返回 Markdown 风格的完整文本。

    - 返回网页标题 + 完整的正文内容
    - 若非 HTML，则返回简单的类型说明
    """
    info = await fetch_url_info(url)
    if not info.get("ok", False):
        return f"抓取失败: {info.get('error', '')}"

    title = info.get("title", "").strip()
    content = info.get("content", "").strip()

    # 简单规范为 Markdown 段落，方便后续 LLM 继续规范化
    parts = []
    if title:
        parts.append(f"# {title}")
    if content:
        parts.append(content)

    if not parts:
        return "页面内容为空或非 HTML。"

    return "\n\n".join(parts)


async def is_guide_url(url: str, name: str = "", skill_name: str = "", callback_config: Dict | None = None) -> bool:
    """
    使用 LLM 异步判断 URL 是否为用户指南、操作指引相关页面，且与技能名称相关。

    Args:
        url: 要判断的 URL
        name: URL 对应的名称（可选）
        skill_name: 技能名称，用于判断 URL 是否与技能相关
        callback_config: 可选的 callback 配置

    Returns:
        True 如果是用户指南/操作指引相关且与技能相关，False 否则
    """
    skill_context = f"\n技能名称: {skill_name}" if skill_name else ""
    if skill_name:
        prompt = f"""请判断以下链接是否同时满足以下两个条件：
1. 是"用户操作指引"、"使用教程"或"操作步骤"类文档页面
2. 与给定的技能名称相关

链接名称: {name if name else '(未提供)'}
链接地址: {url}
技能名称: {skill_name}

请仅根据 URL 和名称判断，不需要访问网页内容。

判断标准：
- URL 或名称必须与技能名称 "{skill_name}" 相关：
  * 主题相关：URL/名称涉及的主题必须与技能名称的主题一致
  * 领域相关：URL/名称所属的领域必须与技能名称的领域一致
  * 功能相关：URL/名称描述的功能必须与技能名称的功能相关
  * 必须与技能名称所包含的意思有区别：用户操作指引的名称应当与技能名称所包含的意思有区别，需要能够提供新的知识内容。如果 URL 或名称只是重复技能名称的含义而没有提供新的知识或不同的视角，应判断为"否"
  * 如果无法判断相关性，或者明显不相关，则应判断为"否"
- 必须是有实质性内容的操作指南，不能是泛化的操作指南：
  * 排除过于泛化、没有具体内容的链接（如"如何使用"、"操作手册"等通用性表述）
  * 必须包含具体的操作步骤、功能点或实质性指导内容
  * 如果 URL 或名称显示为通用性的操作指南而没有明确的实质性内容，应判断为"否"

请只回答 "是" 或 "否"，不要添加其他内容。"""
    else:
        prompt = f"""请判断以下链接是否为"用户操作指引"、"使用教程"或"操作步骤"类文档页面。

链接名称: {name if name else '(未提供)'}
链接地址: {url}

请仅根据 URL 和名称判断，不需要访问网页内容。

判断标准：
- URL 或名称中包含以下关键词或特征，则认为是用户指南/操作指引：
  * 操作步骤、使用指南、快速开始、入门教程
  * 如何、怎样、教程、指南、指引
  * 常见问题、FAQ、帮助文档
  * 配置、设置、部署、安装
  * 其他明显指向用户操作指引的特征

请只回答 "是" 或 "否"，不要添加其他内容。"""

    try:
        messages = [
            {
                "role": "system",
                "content": "你是一个专业的文档分类助手，擅长根据 URL 和名称判断页面类型。"
            },
            {
                "role": "user",
                "content": prompt
            }
        ]

        llm = get_llm()
        response = await llm.ainvoke(
            messages,
            config=callback_config if callback_config else None
        )
        
        content = getattr(response, "content", response)
        if isinstance(content, list):
            content_str = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        else:
            content_str = str(content)
        
        content_str = content_str.strip().lower()
        # 判断返回内容是否表示"是"
        return content_str.startswith("是") or content_str.startswith("yes") or "true" in content_str
        
    except Exception as e:
        # 如果判断失败，默认返回 True，让后续流程继续处理
        print(f"  ⚠️  LLM 判断 URL {url} 失败: {e}，默认继续处理")
        return True


def create_guides_agent():
    """
    使用 langchain.agents.create_agent 创建一个 LangChain Agent：
    - 工具：fetch_guide_page（抓取网页内容）
    - 职责：判断页面是否为“用户操作指引”类文档，并输出规范化 Markdown。

    返回值：
        agent: 一个可通过 agent.invoke(...) 调用的 CompiledGraph
    """
    system_prompt = """你是一个专业的技术文档分析助手，擅长识别"用户操作指引 / 操作步骤 / 使用教程"类网页。
你可以使用工具 fetch_guide_page 根据 URL 抓取网页内容，然后完成以下任务：
1. 判断该页面是否主要是面向终端用户的操作指引文档（包含步骤、前置条件、注意事项等）。
2. 根据判断结果设置 is_valid：
   - is_valid=true：能正确获取到 URL 网页内容，且与用户操作指引相关
   - is_valid=false：不能获取内容或不是操作指引
3. Markdown 要求（仅当 is_valid=true 时）：
   - 使用中文标题和小节，如：# 功能名称、## 前提条件、## 操作步骤、## 注意事项 等；
   - 步骤使用有序列表（1. 2. 3. ...），每一步尽量简明扼要；
   - 可以适当合并、精简冗余内容，但不要改变关键操作逻辑；
   - 必须过滤掉与用户操作无关的内容，包括但不限于：导航栏、页脚、版权信息、法律声明、营销广告、侧边栏、搜索框、登录注册链接等无关信息。
如果 is_valid=false，markdown 字段应为空字符串。"""

    agent = create_agent(
        model=get_llm(),
        tools=[fetch_guide_page],
        system_prompt=system_prompt,
        response_format=ToolStrategy(GuideAnalysisResult),
    )
    return agent


def _sanitize_filename(name: str) -> str:
    """
    将名称转换为安全的文件名（去除特殊字符，保留中文字符、字母、数字、连字符、下划线）。
    """
    # 移除或替换特殊字符，保留中文字符、字母、数字、连字符、下划线
    safe = re.sub(r'[^\w\s\u4e00-\u9fff-]', '', name)
    # 将空格替换为下划线
    safe = re.sub(r'\s+', '_', safe)
    return safe


@observe
async def run_guides_agent(
    index_path: str, 
    skill_dir: str | None = None,
    callback_config: Dict | None = None
) -> List[Dict[str, str]]:
    """
    异步方式使用 LangChain Agent 处理 guides/index.json：
    - 读取 name/url 对
    - 通过 Agent + 网页爬取工具抓取内容
    - 判断是否为用户操作指引
    - 若是，则返回规范化的 Markdown 文本
    - 如果 is_valid=True 且提供了 skill_dir，会将 markdown 保存到 skill_dir/guides/name.md

    Args:
        index_path: guides/index.json 文件路径
        skill_dir: 可选的 skill 目录路径。如果提供且 is_valid=True，会将 markdown 保存到该目录下的 guides/ 子目录
        callback_config: 可选的 callback 配置（包含 callbacks、configurable、metadata 等），用于观测和追踪

    Returns:
        列表，每个元素为：
        {
          "name": 名称,
          "url": 链接,
          "markdown": 规范化后的操作指引 Markdown 内容（如非指引则为空串）,
          "is_valid": 是否为“用户操作指引”相关内容（bool）
        }
    """
    agent = create_guides_agent()
    items = load_guides_index(index_path)

    # 从 skill_dir 提取技能名称
    skill_name = ""
    if skill_dir:
        skill_dir_path = Path(skill_dir)
        skill_name = skill_dir_path.name

    # 使用 LLM 异步过滤，只处理用户指南/操作指引相关的 URL
    print(f"📋 共 {len(items)} 个链接（已去重），开始判断是否为用户指南...")
    if skill_name:
        print(f"  技能名称: {skill_name}")
    
    # 并行执行 is_guide_url 判断
    async def check_item(item: Dict[str, str]) -> tuple[Dict[str, str], bool]:
        name = item["name"]
        url = item["url"]
        is_guide = await is_guide_url(url, name, skill_name, callback_config)
        return item, is_guide
    
    check_results = await asyncio.gather(*[check_item(item) for item in items])
    
    filtered_items = []
    for item, is_guide in check_results:
        if is_guide:
            filtered_items.append(item)
    
    print(f"  ✓ 过滤后剩余 {len(filtered_items)} 个用户指南链接")
    if filtered_items:
        print("  剩余指南列表:")
        for item in filtered_items:
            print(f"    - {item['name']}: {item['url']}\n")
        
        # 根据过滤结果重写 index.json
        try:
            index_path_obj = Path(index_path)
            with index_path_obj.open("r", encoding="utf-8") as f:
                original_data = json.load(f)
            
            # 判断原始数据格式，保持原有格式
            if isinstance(original_data, list):
                # 如果原始是列表，直接写入过滤后的列表
                new_data = filtered_items
            else:
                # 如果原始是对象，保持对象结构，只更新 links 字段
                new_data = original_data.copy()
                new_data["links"] = filtered_items
            
            # 备份原文件
            backup_path = index_path_obj.with_suffix('.json.backup')
            if index_path_obj.exists():
                shutil.copy2(index_path_obj, backup_path)
                print(f"  💾 已备份原 index.json 到 {backup_path.name}")
            
            # 写入新的 index.json
            with index_path_obj.open("w", encoding="utf-8") as f:
                json.dump(new_data, f, ensure_ascii=False, indent=2)
            print(f"  ✅ 已根据过滤结果更新 index.json，保留 {len(filtered_items)} 个有效链接")
        except Exception as e:
            print(f"  ⚠️  更新 index.json 失败: {e}")

    # 并行处理每个过滤后的项目
    async def process_item(item: Dict[str, str]) -> Dict[str, str]:
        name = item["name"]
        url = item["url"]
        print(f"  正在处理: {name}：{url}")

        user_msg = (
            f"下面是一个链接，请判断并根据需要生成操作指引 Markdown：\n"
            f"名称: {name}\n"
            f"URL: {url}\n"
            f"请先使用工具 fetch_guide_page 抓取页面，再根据系统指令输出结果。"
        )

        resp = await agent.ainvoke(
            {
                "messages": [
                    {"role": "user", "content": user_msg},
                ]
            },
            config=callback_config,
        )

        # 从 structured_response 获取结构化结果
        structured_result = resp.get("structured_response")
        if not isinstance(structured_result, GuideAnalysisResult):
            raise ValueError(
                f"Agent 返回结果格式错误: 期望 GuideAnalysisResult，"
                f"实际类型为 {type(structured_result)} (name={name}, url={url})"
            )
        
        is_valid = structured_result.is_valid
        markdown = structured_result.markdown.strip()

        # 如果 is_valid=True 且提供了 skill_dir，保存到文件
        if is_valid and skill_dir:
            guides_dir = os.path.join(skill_dir, "guides")
            os.makedirs(guides_dir, exist_ok=True)

            # 直接使用 index.json 中的 name 作为文件名
            # 只去除可能造成路径问题的字符（路径分隔符）
            filename = name.replace("/", "_").replace("\\", "_")
            md_path = os.path.join(guides_dir, f"{filename}.md")
            with open(md_path, "w", encoding="utf-8") as f:
                f.write(markdown)
        else:
            print(f"  ⏭️  无法获取有效内容（存在安全拦截等情况）: {name} ({url})")

        return {
            "name": name,
            "url": url,
            "markdown": markdown,
            "is_valid": is_valid,
        }
    
    # 并行执行所有处理任务
    results = await asyncio.gather(*[process_item(item) for item in filtered_items])
    return list(results)