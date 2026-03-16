import asyncio
import glob
import os
import json
from pathlib import Path
from typing import List, Dict, Any, Optional

from langfuse import observe

from common import get_llm


class PyScriptEnhancer:
    """
    脚本增强器，用于增强 Python 脚本的文档和类型注解。
    
    支持通过 callback_config 配置 Langchain callbacks（如 Langfuse handler）用于可观测性。
    """
    
    ENHANCE_SYSTEM_PROMPT = '''
你是一名 Python 开发专家，负责增强现有脚本的文档和类型注解。

**核心规则：**
1. **保持原代码不变**：不修改函数名、类名、变量名、代码逻辑和结构
2. **如果是 class**：保持 class 和类方法完全不变，只在外部添加工具函数封装类方法
3. **如果是函数**：添加 docstring（中文）和类型注解
4. **不添加** `if __name__ == "__main__":` 块

**处理方式：**

**Class 处理：**
- 保持 class 定义和所有类方法原样不变
- 在 class 外部添加工具函数，实例化 class 并调用相应方法
- 工具函数需包含：完整 docstring（中文）、类型注解
- 示例：
  ```python
  class DataProcessor:
      def process(self, data: str) -> str:
          return data.upper()
  
  def process_data(input_str: str) -> str:
      """处理输入字符串并返回结果。
      Args:
          input_str: 输入字符串
      Returns:
          str: 处理后的字符串
      """
      processor = DataProcessor()
      return processor.process(input_str)
  ```

**函数处理：**
- 添加完整 docstring（功能描述、参数说明、返回值说明，使用中文）
- 添加类型注解

**输出格式：**

返回 JSON，结构如下：
{
  "enhanced_code": "<增强后的完整 Python 代码>",
  "usage_examples": "<bash 使用示例，纯文本格式>",
  "tool_functions": [
    {
      "name": "<函数名>",
      "signature": "<完整函数签名，如：def func_name(arg: str) -> str>",
      "docstring": "<完整 docstring 内容>"
    }
  ]
}

**usage_examples 格式：**
- 格式：`python scripts/script_name.py function_name [参数]`
- 展示如何调用工具函数或已有函数（不是 class 方法）
- 每个示例后添加功能说明
- 示例：
  ```
  示例1：基本调用
  python scripts/helloworld.py generate_hello_world
  功能：调用 generate_hello_world 函数生成 Hello World 字符串
  
  示例2：带参数调用
  python scripts/processor.py process_data "input" 3
  功能：调用 process_data 函数处理输入字符串
  ```

**tool_functions 说明：**
- 提取所有顶层 `def` 工具函数（不包括类方法、私有函数、特殊方法）
- 如果无工具函数，返回空数组 `[]`

**JSON 转义要求：**
- 所有字符串字段必须正确转义 JSON 特殊字符（双引号、反斜杠等）
- 确保 JSON 可以被 `json.loads()` 成功解析

**输出要求：**
- 只返回 JSON，无其他文字、markdown 代码块或注释
- `enhanced_code` 必须是完整可运行的 Python 代码
'''
    
    def __init__(self, callback_config: Optional[Dict] = None):
        """
        初始化脚本增强器。
        
        Args:
            callback_config: Langchain callbacks 配置（如 Langfuse handler）用于可观测性
        """
        self.callback_config = callback_config or {}
        self.llm = get_llm()
    
    async def _enhance_single_script(self, script_path: Path) -> Dict[str, Any]:
        """调用大模型，增强单个脚本的代码实现。"""
        
        script_content = script_path.read_text(encoding="utf-8")

        messages = [
            {
                "role": "system",
                "content": self.ENHANCE_SYSTEM_PROMPT,
            },
            {
                "role": "user",
                "content": (
                    "下面是需要增强的原始 Python 脚本内容，"
                    "请根据上面的要求进行代码增强：\n\n"
                    f"```python\n{script_content}\n```"
                ),
            },
        ]

        # 使用异步调用 LLM
        response = await self.llm.ainvoke(
            messages,
            config=self.callback_config if self.callback_config else None
        )
        content = getattr(response, "content", response)

        # 解析大模型返回的 JSON
        if isinstance(content, list):
            # ChatOpenAI 在某些版本下 content 可能是 list[dict]
            content_str = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        else:
            content_str = str(content)

        # 清理可能的 markdown 代码块标记
        content_str = content_str.strip()
        
        # 移除开头的 ```json 或 ``` 标记
        if content_str.startswith("```json"):
            content_str = content_str[7:]  # 移除 ```json
        elif content_str.startswith("```"):
            content_str = content_str[3:]  # 移除 ```
        
        # 移除结尾的 ``` 标记
        if content_str.rstrip().endswith("```"):
            content_str = content_str.rstrip()[:-3]
        
        # 再次 strip 去除可能的空白
        content_str = content_str.strip()
        
        try:
            result = json.loads(content_str)
        except json.JSONDecodeError as e:
            print(f"  ⚠️ 警告: JSON 解析失败: {e}")
            return None

        if not isinstance(result, dict) or "enhanced_code" not in result:
            raise ValueError(f"大模型返回格式不符合约定，期望包含 'enhanced_code' 字段: {result}")
        
        # 确保 tool_functions 字段存在且为列表格式
        if "tool_functions" not in result:
            result["tool_functions"] = []
        elif not isinstance(result["tool_functions"], list):
            print(f"  ⚠️ 警告: tool_functions 字段格式不正确，期望列表，实际类型: {type(result['tool_functions'])}")
            result["tool_functions"] = []
        
        # 验证 tool_functions 中每个元素的格式
        validated_tool_functions = []
        for i, func in enumerate(result.get("tool_functions", [])):
            if isinstance(func, dict):
                validated_tool_functions.append({
                    "name": func.get("name", f"unknown_function_{i}"),
                    "signature": func.get("signature", ""),
                    "docstring": func.get("docstring", "")
                })
            else:
                print(f"  ⚠️ 警告: tool_functions[{i}] 格式不正确，期望字典，实际类型: {type(func)}")
        
        result["tool_functions"] = validated_tool_functions

        return result

    @observe
    def enhance_scripts(self, skill_dir: str) -> List[Dict[str, Any]]:
        """
        增强 skill_dir/scripts 目录下的所有 Python 脚本。

        对每个脚本：
        1. 调用大模型，增强代码实现（补充文档、类型注解、调用示例等）；
        2. 将增强后的代码覆盖原脚本文件；
        3. 更新 scripts/README.md，添加使用说明。

        ⚠️ 注意：此函数会直接覆盖原脚本文件，请确保已备份重要脚本。

        Returns:
            List[Dict]: 每个元素包含：
                - name: 脚本名称
                - script_path: 增强后的脚本路径
                - usage_examples: bash 执行示例说明
        """

        skill_path = Path(skill_dir)
        scripts_dir = skill_path / "scripts"

        print(f"📁 正在扫描 skill 脚本目录: {scripts_dir}")

        if not scripts_dir.exists():
            raise FileNotFoundError(f"scripts 目录不存在: {scripts_dir}")

        script_files = [Path(p) for p in glob.glob(os.path.join(str(scripts_dir), "*.py"))]

        if not script_files:
            print("⚠️ 未在 scripts/ 目录下找到任何 .py 脚本，跳过脚本增强。")
            return []

        print(f"🔍 共发现 {len(script_files)} 个脚本，将尝试增强：")
        for path in script_files:
            print(f"   • {path.name}")

        # 异步并发调用大模型
        async def _run_all() -> List[Dict[str, Any]]:
            print("🤖 开始并发调用 LLM，增强脚本代码...")
            tasks = [self._enhance_single_script(path) for path in script_files]
            return await asyncio.gather(*tasks)

        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)

        results = loop.run_until_complete(_run_all())
        print("✅ LLM 调用完成，开始写入增强后的代码...")

        enhanced_scripts: List[Dict[str, Any]] = []

        for script_path, result in zip(script_files, results):
            base_name = script_path.stem
            print(f"  🛠 正在处理脚本: {script_path.name}")

            enhanced_code: str = result["enhanced_code"]
            usage_examples: str = result.get("usage_examples", "")
            tool_functions: List[Dict[str, str]] = result.get("tool_functions", [])

            # 保存增强后的代码（直接覆盖原脚本）
            script_path.write_text(enhanced_code, encoding="utf-8")

            enhanced_scripts.append(
                {
                    "name": base_name,
                    "script_path": str(script_path),
                    "usage_examples": usage_examples,
                    "tool_functions": tool_functions,
                }
            )

        # 更新 references.md 文件（位于 scripts 目录的上一级）
        readme_path = scripts_dir / "../references.md"
        skill_name = skill_path.name  # 获取 skill 目录名称
        self._update_scripts_readme(readme_path, enhanced_scripts, scripts_dir, skill_name)

        print(f"🎉 脚本增强完成，共 {len(enhanced_scripts)} 个。")
        return enhanced_scripts

    def _update_scripts_readme(self, readme_path: Path, scripts: List[Dict[str, Any]], scripts_dir: Path, skill_name: str) -> None:
        """
        更新或创建 references.md 文件（位于 scripts 目录的上一级），添加脚本使用说明。

        Args:
            readme_path: references.md 文件路径
            scripts: 增强后的脚本列表
            scripts_dir: scripts 目录路径
            skill_name: skill 目录名称
        """
        # 读取现有内容（如果存在）
        existing_content = ""
        if readme_path.exists():
            existing_content = readme_path.read_text(encoding="utf-8")
            print(f"  📝 读取现有 references.md: {readme_path.name}")
        else:
            print(f"  📝 创建新的 references.md: {readme_path.name}")

        # 生成最新的脚本使用说明部分
        new_usage_section = self._generate_usage_section(scripts, scripts_dir)

        # 如果文件已存在，则调用大模型对旧内容和新使用说明进行智能合并；否则创建新文件
        if existing_content:
            print("  🔄 检测到现有 references.md，合并原有内容与最新使用说明...")
            new_content = self._merge_usage_sections(
                old_section=existing_content,
                new_section=new_usage_section,
                skill_name=skill_name,
                scripts_dir=scripts_dir,
            )
            print("  ✅ references.md 合并完成")
        else:
            # 创建新文件，使用 skill 名称作为标题
            new_content = f"# {skill_name} Scripts 使用说明\n\n{new_usage_section}"

        # 保存文件
        readme_path.write_text(new_content, encoding="utf-8")
        print(f"  ✅ 已更新 references.md")

    def _generate_usage_section(self, scripts: List[Dict[str, Any]], scripts_dir: Path) -> str:
        """
        生成脚本使用说明部分。

        Args:
            scripts: 增强后的脚本列表
            scripts_dir: scripts 目录路径

        Returns:
            Markdown 格式的使用说明文本
        """
        if not scripts:
            return ""

        section = "## Python脚本使用说明\n\n"
        section += "本目录包含增强后的 Python 脚本，已添加完整的文档说明、类型注解和使用示例。\n\n"

        # 生成脚本列表和使用示例
        section += "### 可用脚本\n\n"
        for script in scripts:
            script_name = script.get("name", "unknown")
            script_path = Path(script.get("script_path", ""))
            usage_examples = script.get("usage_examples", "")
            
            # 获取相对路径
            script_rel = os.path.relpath(script_path, scripts_dir)
            
            section += f"#### {script_name}\n\n"
            section += f"- **脚本文件**: `{script_rel}`\n\n"
            
            # 展示工具函数定义和 docstring
            tool_functions = script.get("tool_functions", [])
            if tool_functions:
                section += f"**工具函数：**\n\n"
                for func in tool_functions:
                    func_name = func.get("name", "")
                    func_signature = func.get("signature", "")
                    func_docstring = func.get("docstring", "")
                    
                    section += f"- **{func_name}**\n\n"
                    section += f"  ```python\n"
                    section += f"  {func_signature}\n"
                    section += f"  ```\n\n"
                    
                    if func_docstring:
                        section += f"  {func_docstring.strip()}\n\n"
            
            if usage_examples:
                section += f"**使用示例：**\n\n"
                section += f"{usage_examples}\n\n"
            else:
                section += f"**使用方式：**\n\n"
                section += f"```bash\n"
                section += f"python {script_rel}\n"
                section += f"```\n\n"
        
        return section

    def _merge_usage_sections(
        self,
        old_section: str,
        new_section: str,
        skill_name: str,
        scripts_dir: Path,
    ) -> str:
        """
        使用大模型智能合并旧的和新的脚本使用说明片段。

        Args:
            old_section: 旧的 README 内容
            new_section: 新生成的使用说明
            skill_name: 当前 skill 名称
            scripts_dir: scripts 目录路径

        Returns:
            合并后的 README 内容
        """

        system_prompt = """
你是一名资深技术文档工程师，负责帮用户合并脚本使用说明文档。
用户有一份旧的 README 片段（包含手工修改和旧的脚本使用方式描述），以及一份新的自动生成片段（包含最新的脚本使用说明和示例）。
你的任务是：
- 识别旧片段中已经被增强的脚本（例如某些脚本原来缺少文档，现在已经有了完整的使用说明）；
- 保留这些脚本的自然语言描述/上下文说明，但将其中的使用方式更新为最新的说明；
- 合并新片段中的脚本列表和使用示例，确保包含所有最新脚本。
重点：
1. 保留并优先使用旧片段中用户可能手动添加或修改的说明文字（尤其是对脚本含义、用途的解释）。
2. 对于已经增强的脚本，将旧的使用说明更新为最新的使用方式（可以参考新片段中的示例）。
3. 你可以调整排版和结构，使其更清晰、易读，但不要丢失关键信息。
4. 不要添加额外的注释或解释，只输出最终的 Markdown 内容。
"""

        user_prompt = f"""
Skill 名称: {skill_name}
脚本目录: {scripts_dir}

下面是旧的 README 内容：
---------------- OLD_SECTION_START ----------------
{old_section}
---------------- OLD_SECTION_END ------------------

下面是新的自动生成使用说明片段：
---------------- NEW_SECTION_START ----------------
{new_section}
---------------- NEW_SECTION_END ------------------

请根据 system 指令，输出**合并后的完整 README 内容**，要求：
- 直接输出最终的 Markdown 文本
- 不要添加任何额外说明或解释
    """

        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        response = self.llm.invoke(
            messages,
            config=self.callback_config if self.callback_config else None
        )
        content = getattr(response, "content", response)
        merged = content if isinstance(content, str) else str(content)

        # 清理输出（去除首尾空白）
        merged = merged.strip()

        return merged