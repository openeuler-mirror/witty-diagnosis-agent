from common import get_llm

def md_formatter(md_content, callback_config=None):
    prompt = f"""
    你是一个专业的Markdown格式化专家。请对以下从PDF提取的文本进行规范化处理：

    任务：
    1. 修复格式问题（多余空行、不规范的标题等）
    2. 优化段落结构，精确描述，不要总结，不要概述
    3. 确保代码块正确格式化
    4. 统一列表和表格格式
    5. 保持内容完整性，不删除重要信息
    6. 对于重要的**版本信息、内核信息、系统信息**需要精确保留
    7. 去除无关内容（例如：意见反馈、网站备案信息、版权声明、联系方式、页眉页脚等非正文内容）
    

    输出要求：
    - 符合标准Markdown语法
    - 保持原文语义不变
    - 使用适当的标题层级
    - 代码块使用正确的语言标识

    注意：只输出修改后的内容，不要包含思考过程或者其他信息

    当前输入的文本内容为：{md_content}
    """
    llm = get_llm()
    message = llm.invoke([{
        "role": "user",
        "content": prompt
    }], config=callback_config if callback_config else None)
    return message.content