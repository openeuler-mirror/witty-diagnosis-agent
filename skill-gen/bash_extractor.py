"""
从输入文档中整理提取出可以执行的bash脚本

该模块提供从文本中提取零散的bash命令，并将它们组合成单个可执行脚本的功能。
使用LLM进行智能识别和提取。
"""

import json
from pathlib import Path
from typing import Dict, Any, Optional, Union
from pydantic import BaseModel, Field

from langfuse import observe

from common import get_llm


class BashScriptResponse(BaseModel):
    """Bash脚本提取结果输出格式"""
    script_content: str = Field(..., description="生成的完整bash脚本内容")
    description: str = Field(..., description="脚本功能描述")
    script_name: Optional[str] = Field(
        default=None,
        description="根据脚本功能生成的脚本文件名（不含路径，例如 collect_oom_diagnostics.sh）",
    )
    is_valid: bool = Field(..., description="判断提取结果是否包含有效脚本。如果文档中没有可提取的数据采集命令，或提取的脚本内容无效（如只有注释、shebang等），应设置为false")


class BashExtractor:
    """
    Bash命令提取器，用于从文本中提取零散的bash命令并组合成可执行脚本。
    
    使用LLM直接识别和提取命令。
    """
    
    EXTRACT_SYSTEM_PROMPT = """
你是一名资深的Linux运维专家，根据文档中已有的数据采集和分析相关的bash命令生成可执行脚本。

**核心原则：严格基于文档内容，禁止添加文档中不存在的命令或参数**

**任务：**
只提取文档中明确出现的查看、检查、诊断、监控等数据采集Bash命令，不提取安装、配置、修改等执行措施命令或者其他类型（如python)脚本。

**提取规则：**
1. **严格按文档提取（最重要）**：
   - **只提取文档中明确出现的命令**，不能添加、修改或臆造命令
   - 保持命令的原始参数、选项和路径，不能随意更改
   - 如果文档中命令不完整，只提取文档中存在的部分，不能补充
   - 示例：文档中是 `cat /proc/sys/vm/panic_on_oom`，不能改为 `cat /proc/sys/vm/*` 或添加其他文件

2. **命令类型**：
   - ✅ 提取：`cat`、`grep`、`ps`、`df`、`free`、`top`、`tail`、`dmesg`、`ntpq`等查看类命令
   - ❌ 不提取：`yum install`、`systemctl restart`、`vim`、`echo >`、`mkdir`、`rm`等操作类命令

3. **参数处理（非常重要）**：
   - **必须识别文档中的示例参数**：如进程名（test、nginx等）、PID（1234、5678等）、IP地址（192.168.1.1、example.com等）、端口号、文件路径等
   - **禁止硬编码示例值**：不能直接在脚本中使用 "test"、"1234" 等示例值，必须将其封装为脚本命令行参数
   - **参数化规则**：
     * 如果文档中命令包含明显的示例值（如 `ps -ef | grep test`、`kill 1234`），必须将 "test"、"1234" 等替换为 `$1`、`$2` 等参数，并在脚本说明中明确这些参数含义（例如 `$1`=要检查的进程名）
     * 如果文档只是用 "test" 作为示例进程名，而没有要求“必须检查名为 test 的进程”，**脚本中不允许继续出现字面量 `test`**，只能通过参数（如 `$PROCESS_NAME`、`$1`）由用户传入
     * 根据文档中命令的用途来命名参数（如"检查指定进程"→参数名应为 `PROCESS_NAME` 或 `$1` 表示进程名）
     * 如果文档明确说明了参数的目的，应根据目的命名参数，而不是使用示例值
   - 使用 `$1`, `$2` 或 `getopts` 处理参数
   - 脚本开头必须添加参数验证、使用说明和示例用法
   - **参数值必须来自文档**，不能添加文档中未提及的参数

4. **错误处理**：
   - **不使用 `set -e`**，单个命令失败不中断脚本执行
   - 每个命令前检查是否存在：`command -v <cmd> || echo "警告: 命令未找到，跳过"`
   - 每个命令后检查执行结果：`<cmd> || echo "警告: 执行失败"`
   - 检查文件是否存在：`[ -f "<file>" ] || echo "警告: 文件不存在，跳过"`
   - 所有错误仅输出警告，不退出脚本
   - **错误处理代码可以添加，但核心命令必须严格来自文档**

5. **脚本结构**：
   - 包含 `#!/bin/bash` shebang
   - 使用 `set -u` 检查未定义变量（不使用 `set -e`）
   - 添加步骤注释
   - 移除命令前的 `$`、`#` 提示符

**输出格式（JSON）：**
{
  "script_content": "<完整bash脚本>",
  "description": "<脚本功能描述>",
  "script_name": "<脚本文件名，例如 collect_oom_diagnostics.sh>",
  "is_valid": <true/false>
}

**is_valid 字段说明：**
- 如果文档中包含可提取的数据采集分析Bash命令，且生成的脚本包含有效的可执行Bash命令（去除注释和shebang后仍有实际命令），设置为 `true`
- 如果文档中没有可提取的数据采集命令，或提取的脚本内容无效（去除注释和shebang后为空或只有空白），设置为 `false`
- 此字段用于判断提取结果是否有效，必须准确反映脚本的实际有效性

**脚本命名要求（script_name）：**
- 必须能体现脚本的主要用途，例如：`collect_oom_diagnostics.sh`、`check_ntp_status.sh`
- 建议使用 **小写英文 + 数字 + 下划线/中划线** 组合
- 必须以 `.sh` 结尾
- 只包含文件名本身，不包含路径（不能包含 `/`、`\\` 等路径分隔符）
- 尽量简短清晰，避免过长（建议不超过 60 个字符）

**关键要求总结：**
1. **严格按文档提取**：只提取文档中明确出现的命令，保持原始参数和选项
2. **参数化处理**：识别文档中的示例值（进程名、PID、IP等），禁止硬编码，必须替换为脚本参数（$1, $2 或 getopts）
3. **错误处理**：每个命令添加错误处理，失败时输出警告但不退出，单个失败不影响其他命令
4. **脚本信息**：根据脚本功能概括清晰的描述（description），设计含义明确的文件名（script_name）

**输出要求：**
- 只返回JSON，无其他文字
- 正确转义JSON特殊字符
- `script_content` 必须是完整可运行的bash脚本
"""
    
    def __init__(self, callback_config: Optional[Dict] = None):
        """
        初始化Bash命令提取器。
        
        Args:
            callback_config: Langchain callbacks配置（如Langfuse handler）用于可观测性
        """
        self.callback_config = callback_config or {}
        self.llm = get_llm()
    
    async def _extract_with_llm(
        self, 
        text: str
    ) -> BashScriptResponse:
        """使用LLM直接调用提取命令。"""
        
        user_prompt = f"""
请从以下文本中提取数据采集和分析相关的bash命令，生成可执行脚本。

**文本内容：**
{text}

请严格按照 system 指令中的要求，生成完整的bash脚本及其配套的 JSON 结构。
"""
        
        messages = [
            {"role": "system", "content": self.EXTRACT_SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ]
        
        # 使用异步调用LLM
        response = await self.llm.ainvoke(
            messages,
            config=self.callback_config if self.callback_config else None
        )
        content = getattr(response, "content", response)
        
        # 解析大模型返回的JSON
        if isinstance(content, list):
            content_str = "".join(part.get("text", "") for part in content if isinstance(part, dict))
        else:
            content_str = str(content)
        
        # 清理可能的markdown代码块标记
        content_str = content_str.strip()
        if content_str.startswith("```json"):
            content_str = content_str[7:]
        elif content_str.startswith("```"):
            content_str = content_str[3:]
        if content_str.rstrip().endswith("```"):
            content_str = content_str.rstrip()[:-3]
        content_str = content_str.strip()
        
        try:
            result = json.loads(content_str)
        except json.JSONDecodeError as e:
            raise ValueError(f"LLM返回的JSON解析失败: {e}\n原始内容: {content_str[:500]}")
        
        # 验证返回格式
        if not isinstance(result, dict):
            raise ValueError(f"LLM返回格式不符合约定，期望字典: {result}")
        
        # 确保所有必需字段存在
        if "script_content" not in result:
            raise ValueError("LLM返回缺少 'script_content' 字段")
        if "description" not in result:
            result["description"] = "从文本中提取的bash命令脚本"
        # script_name 字段可选，如果不存在则置为 None
        if "script_name" not in result:
            result["script_name"] = None
        # is_valid 字段必需，如果不存在则默认为 False
        if "is_valid" not in result:
            result["is_valid"] = False
        
        return BashScriptResponse(**result)
    
    def _save_script(
        self, 
        script_response: BashScriptResponse, 
        output_path: Union[str, Path]
    ) -> Path:
        """
        将提取的脚本保存到文件（内部方法）。
        
        Args:
            script_response: BashScriptResponse对象
            output_path: 输出文件路径
            
        Returns:
            Path: 保存的文件路径
        """
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(script_response.script_content, encoding="utf-8")
        # 添加执行权限
        output_path.chmod(0o755)
        return output_path
    
    @observe
    def extract_scripts_from_references(
        self, 
        skill_dir: Union[str, Path], 
        references_text: str
    ) -> Dict[str, Any]:
        """
        从拼接后的 references 文本内容中提取bash命令，生成脚本并保存到 skill_dir/scripts 目录。
        
        Args:
            skill_dir: skill目录路径
            references_text: 拼接后的参考文件内容文本
            
        Returns:
            Dict: 包含：
                - script_path: 生成的脚本路径
                - description: 脚本描述
        """
        import asyncio
        
        skill_path = Path(skill_dir)
        scripts_dir = skill_path / "scripts"
        
        if not references_text or not references_text.strip():
            print("⚠️  没有参考文件内容，跳过bash脚本提取。")
            return {}
        
        # 确保 scripts 目录存在
        scripts_dir.mkdir(parents=True, exist_ok=True)
        
        print("🤖 开始调用 LLM，从参考文件中提取bash命令...")
        
        # 异步提取
        async def _extract() -> BashScriptResponse:
            return await self._extract_with_llm(references_text)
        
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
        
        result = loop.run_until_complete(_extract())
        print("✅ LLM 调用完成，开始检查提取结果...")

        # 根据模型的 is_valid 字段判断提取结果是否有效
        if not result.is_valid:
            print("⚠️  未提取到任何有效命令，跳过脚本生成与保存。")
            return {}

        print("✅ 检测到有效命令，开始保存生成的脚本...")
        
        # 直接使用模型返回的脚本名称；如无则回退为默认名称
        script_name = (result.script_name or "extracted_commands.sh").strip()
        script_path = scripts_dir / script_name
        
        print(f"  🛠  正在保存脚本: {script_path.name}")
        
        # 保存脚本
        self._save_script(result, script_path)
            
        print(f"🎉 Bash脚本提取完成，脚本已保存到: {script_path}")
        
        return {
            "script_path": str(script_path),
            "description": result.description,
        }