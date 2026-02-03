import os
import logging
from typing import List


def check_environment_variables(required_vars: List[str]) -> None:
    """检查必要的环境变量是否存在。"""
    missing_vars = [var for var in required_vars if not os.getenv(var)]

    if missing_vars:
        logging.error(f"错误: 缺少必要的环境变量: {', '.join(missing_vars)}")
        logging.error("请参考 .env.example 文件，配置 .env 环境变量。")
        exit(1)


def format_header(
    title: str, width: int = 60, min_width: int = 20, char: str = "="
) -> str:
    """
    格式化输出标题，带有上下分隔线。会自动调整宽度以适应标题长度。

    Args:
        title: 标题内容
        width: 目标宽度，如果标题较长会自动扩展
        min_width: 最小宽度，确保标题较短时也有一定宽度
        char: 分隔字符

    Returns:
        格式化后的字符串

    Example:
        >>> print(format_header("TEST", width=10))
        ==========
           TEST
        ==========
    """
    lines = []

    # 确保宽度至少为 min_width，且不小于标题长度 + 4（左右各 2 个空格）
    final_width = max(width, min_width, len(title) + 4)
    lines.append(char * final_width)

    # 计算居中所需的空格
    padding = (final_width - len(title)) // 2
    lines.append(" " * padding + title)
    lines.append(char * final_width)
    return "\n".join(lines)
