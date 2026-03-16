import re
import uuid

from common import get_llm


SYSTEM_PROMPT = """
你是一名资深技术文档整理助手，负责为 Claude Skill 生成名称。

生成规则（需符合 SKILL.md.example 中 name 字段约束）：
1. 使用简短、精炼的英文或拼音关键词，能概括文档主要能力或场景（如：os-oom-diagnostics、linux-disk-full、ntp-sync）。
2. 只能包含小写字母 `a-z`、数字 `0-9` 和短横线 `-`，**不允许使用下划线 `_`、空格或其他符号**。
3. 不要包含中文或任何标点符号（除了短横线 `-`）。
4. 总长度最多 64 个字符，推荐控制在 30 个字符以内。
5. 生成的名称应与目录名称匹配，作为 Claude Skill 的唯一标识符。
6. 输出中**只返回最终的 skill name 本身**，不要添加任何解释、引号或前后缀。
"""


def gen_skill_name_from_text(text: str, max_length: int = 60, *, fallback_prefix: str = "skill") -> str:
    """
    根据输入技术文档/案例文本，生成一个可用作目录名的 skill name。

    Args:
        text: 技术文档或案例的全文/摘要内容。
        max_length: 生成的 skill name 允许的最大长度（默认 60）。
        fallback_prefix: 当模型返回异常或清洗后为空时使用的前缀。

    Returns:
        处理后的 skill name 字符串，仅包含小写字母、数字、-、_。
    """
    if not text or not text.strip():
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    messages = [
        {
            "role": "system",
            "content": SYSTEM_PROMPT,
        },
        {
            "role": "user",
            "content": (
                "请基于下面的技术文档内容，生成一个符合规则的 skill name：\n\n"
                f"{text}"
            ),
        },
    ]

    try:
        llm = get_llm()
        response = llm.invoke(messages)
        content = getattr(response, "content", response)

        if isinstance(content, list):
            # 兼容部分模型返回 list[dict] 的格式
            raw_name = "".join(
                part.get("text", "") for part in content if isinstance(part, dict)
            )
        else:
            raw_name = str(content)
    except Exception:
        # 调用失败时退回到随机名称
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    # ----- 本地安全清洗：只保留 a-z / 0-9 / -，并控制长度 -----
    if not raw_name:
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    # 只取第一行，避免说明文字
    name = str(raw_name).strip().splitlines()[0].lower()

    # 只允许 a-z0-9-，其他全部替换为 -
    name = re.sub(r"[^a-z0-9-]+", "-", name)
    # 合并多余的 -
    name = re.sub(r"-{2,}", "-", name)
    # 去掉首尾 -
    name = name.strip("-")

    # 生效的最大长度不超过 64
    effective_max = min(max_length, 64)
    if len(name) > effective_max:
        name = name[:effective_max].rstrip("-")

    if not name:
        name = f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    return name


async def agen_skill_name_from_text(
    text: str, max_length: int = 60, *, fallback_prefix: str = "skill"
) -> str:
    """
    异步版本：根据输入文本生成 skill name。
    """
    if not text or not text.strip():
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    messages = [
        {
            "role": "system",
            "content": SYSTEM_PROMPT,
        },
        {
            "role": "user",
            "content": (
                "请基于下面的技术文档内容，生成一个符合规则的 skill name：\n\n"
                f"{text}"
            ),
        },
    ]

    try:
        llm = get_llm()
        response = await llm.ainvoke(messages)
        content = getattr(response, "content", response)

        if isinstance(content, list):
            raw_name = "".join(
                part.get("text", "") for part in content if isinstance(part, dict)
            )
        else:
            raw_name = str(content)
    except Exception:
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    if not raw_name:
        return f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    name = str(raw_name).strip().splitlines()[0].lower()
    name = re.sub(r"[^a-z0-9-]+", "-", name)
    name = re.sub(r"-{2,}", "-", name)
    name = name.strip("-")

    effective_max = min(max_length, 64)
    if len(name) > effective_max:
        name = name[:effective_max].rstrip("-")

    if not name:
        name = f"{fallback_prefix}_{uuid.uuid4().hex[:8]}"

    return name

