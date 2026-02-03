#!/usr/bin/env python3
"""
元数据提取模块

根据技能内容和元数据格式模板，使用大模型生成 YAML 前置元数据。
"""

from typing import Optional
from common import get_llm


def extract_meta_data(content: str, meta_data_format: str, callback_config=None, skill_name: Optional[str] = None) -> Optional[str]:
    """
    根据技能内容和元数据格式模板，使用大模型生成 YAML 前置元数据。

    Args:
        content: 技能的主体内容（不包含元数据）
        meta_data_format: 元数据格式模板（YAML 格式的字符串）
        callback_config: Langfuse 回调配置（可选）
        skill_name: 技能名称（可选）

    Returns:
        生成的 YAML 元数据字符串（不包含 --- 包裹），如果生成失败则返回 None
    """
    skill_name_section = ""
    if skill_name:
        skill_name_section = f"\n技能名称为：{skill_name}\n"
    
    prompt = f"""你是一个专业的元数据生成专家。请根据提供的技能内容和元数据格式模板，生成符合要求的 YAML 元数据。
{skill_name_section}
技能内容：
```markdown
{content}
```

元数据格式模板：
```yaml
{meta_data_format}
```

任务要求：
1. 仔细分析技能内容，理解技能的核心功能和用途
2. 参考元数据格式模板，生成符合格式要求的 YAML 元数据
3. 确保所有必需字段都已填写（如 name、description 等）
4. 元数据内容应该准确反映技能的实际功能和特点
5. 如果模板中有可选字段，根据技能内容判断是否需要包含

输出要求：
- 仅输出 YAML 格式的元数据内容（不包含 --- 包裹）
- 确保 YAML 格式正确，可以正常解析
- 确保所有字段值都是有效的字符串或数字
- 不要包含任何额外的说明或注释

输出：
仅返回 YAML 元数据内容，不要包含 --- 包裹，不要包含其他说明。
"""

    try:
        llm = get_llm()
        message = llm.invoke(
            [{
                "role": "user",
                "content": prompt
            }],
            config=callback_config if callback_config else None
        )
        meta_data = message.content.strip()
        
        # 移除可能的 ---
        if meta_data.startswith("---"):
            meta_data = meta_data[3:].lstrip()
            if meta_data.endswith("---"):
                meta_data = meta_data[:-3].rstrip()
        
        return meta_data
    except Exception as e:
        print(f"  ⚠️  生成元数据时发生错误: {e}")
        return None
