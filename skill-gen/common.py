import os
import re
import httpx
import yaml
from langchain_openai import ChatOpenAI


def get_llm():
    llm = ChatOpenAI(
        model=os.getenv("DEEPSEEK_MODEL"),
        base_url=os.getenv("DEEPSEEK_BASE_URL"),
        api_key=os.getenv("DEEPSEEK_API_KEY"),
        temperature=0,
        http_client=httpx.Client(verify=False),
        http_async_client=httpx.AsyncClient(verify=False),
    )
    return llm


def validate_skill_format(content: str) -> bool:
    """
    验证 SKILL.md 格式是否正确，检查是否有 --- 包裹的内容，且
    name / description / 正文（prompt）均为非空。

    Args:
        content: 生成的 SKILL.md 内容

    Returns:
        True 如果格式正确且关键字段非空，否则 False
    """
    if not content or not content.strip():
        print("错误: SKILL.md 内容为空")
        return False

    # 使用正则表达式提取 YAML 前置区
    yaml_pattern = r"^---\n(.*?)\n---"
    yaml_match = re.search(yaml_pattern, content, re.DOTALL | re.MULTILINE)
    if not yaml_match:
        print("错误: 未找到 YAML 前置区（缺少 --- 包裹的元数据）")
        return False

    # 解析 YAML 元数据
    yaml_content = yaml_match.group(1).strip()
    if not yaml_content:
        print("错误: YAML 前置区内容为空")
        return False

    try:
        meta_data = yaml.safe_load(yaml_content) or {}
    except Exception as e:
        # YAML 解析失败视为无效
        print(f"错误: YAML 解析失败 - {e}")
        return False

    if not isinstance(meta_data, dict):
        print(f"错误: YAML 元数据不是字典类型，实际类型: {type(meta_data)}")
        return False

    # 校验 name / description 非空
    name = str(meta_data.get("name", "")).strip()
    description = str(meta_data.get("description", "")).strip()
    if not name or not description:
        missing_fields = []
        if not name:
            missing_fields.append("name")
        if not description:
            missing_fields.append("description")
        print(f"错误: 缺少必需的元数据字段: {', '.join(missing_fields)}")
        return False

    # 提取主体内容（移除 YAML 前置区），作为 prompt 进行非空校验
    main_content = re.sub(
        yaml_pattern, "", content, flags=re.DOTALL | re.MULTILINE
    ).strip()
    if not main_content:
        print("错误: SKILL.md 主体内容（prompt）为空")
        return False

    return True
