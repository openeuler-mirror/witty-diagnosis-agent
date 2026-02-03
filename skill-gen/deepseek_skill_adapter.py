#!/usr/bin/env python3
"""
DeepSeek AI Adaptor

Implements platform-specific handling for DeepSeek AI (Anthropic) skills.
Refactored from upload_skill.py and enhance_skill.py.
"""

import os
import re
import zipfile
import asyncio
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime
from langfuse import observe

from common import get_llm, validate_skill_format
from markdown_formatter import md_formatter
from pyscript_enhance import PyScriptEnhancer
from bash_extractor import BashExtractor
from extract_meta_data import extract_meta_data
from guides_extractor import run_guides_agent

from skill_seekers.cli.adaptors.base import SkillAdaptor, SkillMetadata


class DeepSeekAdaptor(SkillAdaptor):
    """
    DeepSeek AI platform adaptor with Langfuse observability support.

    Handles:
    - YAML frontmatter format for SKILL.md
    - ZIP packaging with standard Claude skill structure
    - Upload to Anthropic Skills API
    - AI enhancement using DeepSeek API
    - Langfuse observability through callbacks
    """

    PLATFORM = "DeepSeek"
    PLATFORM_NAME = "DeepSeek AI"
    DEFAULT_API_ENDPOINT = "https://api.deepseek.com/"

    def __init__(self, config: Optional[Dict[str, Any]] = None, callback_config: Optional[Dict] = None):
        """
        初始化 DeepSeek 适配器

        Args:
            config: Platform-specific configuration options
            callback_config: config of Langchain callbacks (e.g., Langfuse handler) for observability
        """
        super().__init__(config)
        self.callback_config = callback_config or {}
        self.llm = get_llm()

    def format_skill_md(self, skill_dir: Path, metadata: SkillMetadata) -> str:
        """
        Format SKILL.md with Claude's YAML frontmatter.

        Args:
            skill_dir: Path to skill directory
            metadata: Skill metadata

        Returns:
            Formatted SKILL.md content with YAML frontmatter
        """
        # Read existing content (if any)
        existing_content = self._read_existing_content(skill_dir)

        # If existing content already has proper structure, use it
        if existing_content and len(existing_content) > 100:
            content_body = existing_content
        else:
            # Generate default content
            content_body = f"""# {metadata.name.title()} Documentation Skill

{metadata.description}

## When to use this skill

Use this skill when the user asks about {metadata.name} documentation, including API references, tutorials, examples, and best practices.

## What's included

This skill contains comprehensive documentation organized into categorized reference files.

{self._generate_toc(skill_dir)}
"""

        # Format with YAML frontmatter
        return f"""---
name: {metadata.name}
description: {metadata.description}
version: {metadata.version}
---

{content_body}
"""

    def package(self, skill_dir: Path, output_path: Path) -> Path:
        """
        Package skill into ZIP file.

        Creates standard Claude skill structure:
        - SKILL.md
        - references/*.md
        - scripts/ (optional)
        - assets/ (optional)

        Args:
            skill_dir: Path to skill directory
            output_path: Output path/filename for ZIP

        Returns:
            Path to created ZIP file
        """
        skill_dir = Path(skill_dir)

        # Determine output filename
        if output_path.is_dir() or str(output_path).endswith('/'):
            output_path = Path(output_path) / f"{skill_dir.name}.zip"
        elif not str(output_path).endswith('.zip'):
            output_path = Path(str(output_path) + '.zip')

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Create ZIP file
        with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            # Add SKILL.md (required)
            skill_md = skill_dir / "SKILL.md"
            if skill_md.exists():
                zf.write(skill_md, "SKILL.md")

            # Add references.md (if exists)
            references_md = skill_dir / "references.md"
            if references_md.exists():
                zf.write(references_md, "references.md")

            # Add references directory (if exists)
            refs_dir = skill_dir / "references"
            if refs_dir.exists():
                for ref_file in refs_dir.rglob("*"):
                    if ref_file.is_file() and not ref_file.name.startswith('.'):
                        arcname = ref_file.relative_to(skill_dir)
                        zf.write(ref_file, str(arcname))

            # Add scripts directory (if exists)
            scripts_dir = skill_dir / "scripts"
            if scripts_dir.exists():
                for script_file in scripts_dir.rglob("*"):
                    if script_file.is_file() and not script_file.name.startswith('.'):
                        arcname = script_file.relative_to(skill_dir)
                        zf.write(script_file, str(arcname))

            # Add assets directory (if exists)
            assets_dir = skill_dir / "assets"
            if assets_dir.exists():
                for asset_file in assets_dir.rglob("*"):
                    if asset_file.is_file() and not asset_file.name.startswith('.'):
                        arcname = asset_file.relative_to(skill_dir)
                        zf.write(asset_file, str(arcname))

            # Add guides directory (if exists)
            guides_dir = skill_dir / "guides"
            if guides_dir.exists():
                for guide_file in guides_dir.rglob("*"):
                    if guide_file.is_file() and not guide_file.name.startswith('.'):
                        if guide_file.suffix == '.md':
                            arcname = guide_file.relative_to(skill_dir)
                            zf.write(guide_file, str(arcname))

        return output_path

    def cleanup_intermediate_files(self, skill_dir: Path) -> None:
        """
        清理生成 skill 过程中产生的中间文件。

        会执行以下操作：
        - 删除 skill_dir 同级目录下的 "<skill-name>-extracted.json"
        - 删除 skill_dir/guides/index.json
        - 删除 skill_dir 下面的空目录

        Args:
            skill_dir: Path to skill directory
        """
        skill_dir = Path(skill_dir)

        # 1. 删除同级目录下的 <skill-name>-extracted.json
        extracted_json = skill_dir.parent / f"{skill_dir.name}_extracted.json"
        if extracted_json.exists():
            try:
                extracted_json.unlink()
                print(f"  🧹 Removed intermediate file: {extracted_json}")
            except Exception as e:
                print(f"  ⚠️  Failed to remove {extracted_json}: {e}")

        # 2. 删除 guides/index.json 及其备份
        guides_index = skill_dir / "guides" / "index.json"
        guides_index_backup = skill_dir / "guides" / "index.json.backup"

        for path in (guides_index, guides_index_backup):
            if path.exists():
                try:
                    path.unlink()
                    print(f"  🧹 Removed guides index file: {path}")
                except Exception as e:
                    print(f"  ⚠️  Failed to remove {path}: {e}")

        # 如果 guides 目录已为空，则尝试删除
        guides_dir = skill_dir / "guides"
        try:
            if guides_dir.exists() and not any(guides_dir.iterdir()):
                guides_dir.rmdir()
                print(f"  🧹 Removed empty directory: {guides_dir}")
        except Exception as e:
            print(f"  ⚠️  Failed to remove guides directory {guides_dir}: {e}")

        # 3. 删除 skill_dir 下的空目录（自底向上）
        for root, dirs, _files in os.walk(skill_dir, topdown=False):
            for d in dirs:
                dir_path = Path(root) / d
                try:
                    if dir_path.exists() and dir_path.is_dir() and not any(dir_path.iterdir()):
                        dir_path.rmdir()
                        print(f"  🧹 Removed empty directory: {dir_path}")
                except Exception as e:
                    print(f"  ⚠️  Failed to remove empty directory {dir_path}: {e}")

    def upload(self, package_path: Path, api_key: str, **kwargs) -> Dict[str, Any]:
        """
        Upload skill ZIP to Anthropic Skills API.

        Args:
            package_path: Path to skill ZIP file
            api_key: Anthropic API key
            **kwargs: Additional arguments (timeout, etc.)

        Returns:
            Dictionary with upload result
        """
        raise NotImplementedError("该适配器不支持上传skill")

    def validate_api_key(self, api_key: str) -> bool:
        """
        Validate Anthropic API key format.

        Args:
            api_key: API key to validate

        Returns:
            True if key starts with 'sk-ant-'
        """
        return api_key.strip().startswith('sk-ant-')

    def get_env_var_name(self) -> str:
        """
        Get environment variable name for Anthropic API key.

        Returns:
            'DEEPSEEK_API_KEY'
        """
        return "DEEPSEEK_API_KEY"

    def supports_enhancement(self) -> bool:
        """
        DeepSeek supports AI enhancement via Anthropic API.

        Returns:
            True
        """
        return True

    def enhance_reference(self, skill_dir: Path) -> bool:
        """
        增强 reference 文件

        Args:
            skill_dir: Path to skill directory
            callbacks: Optional callbacks for observability (overrides instance callbacks)

        Returns:
            True if enhancement succeeded
        """
        references_dir = skill_dir / "references"
        if not references_dir.exists():
            return True

        # Read all .md files
        for ref_file in sorted(references_dir.glob("*.md")):
            print(f"  📖 Formatting {ref_file.name}...")
            content = ref_file.read_text(encoding='utf-8')
            enhance_content = md_formatter(content, self.callback_config)
            ref_file.write_text(enhance_content, encoding='utf-8')
            print(f"  ✅ Saved enhanced {ref_file.name}")

        return True

    @observe
    def enhance(self, skill_dir: Path, api_key: str) -> bool:
        """
        Enhance SKILL.md using DeepSeek API with Langfuse observability.

        Reads reference files, sends them to DeepSeek, and generates
        an improved SKILL.md with real examples and better organization.

        Args:
            skill_dir: Path to skill directory
            api_key: DeepSeek API key
        Returns:
            True if enhancement succeeded
        """

        skill_dir = Path(skill_dir)
        references_dir = skill_dir / "references"
        skill_md_path = skill_dir / "SKILL.md"

        # Read reference files
        print("📖 Reading reference documentation...")
        references = self._read_reference_files(references_dir)

        if not references:
            print("❌ No reference files found to analyze")
            return False

        print(f"  ✓ Read {len(references)} reference files")
        total_size = sum(len(c) for c in references.values())
        print(f"  ✓ Total size: {total_size:,} characters\n")

        # 处理 guides/index.json（如果存在）
        guides = {}
        guides_dir = skill_dir / "guides"
        guides_index_path = guides_dir / "index.json"
        if guides_index_path.exists():
            print("📖 Processing guides/index.json...")
            try:
                # 调用 guides_extractor 处理 index.json
                guides_results = asyncio.run(
                    run_guides_agent(
                        index_path=str(guides_index_path),
                        skill_dir=str(skill_dir),
                        callback_config=self.callback_config
                    )
                )
                
                # 读取生成的 guides markdown 文件
                for guide_file in sorted(guides_dir.glob("*.md")):
                    try:
                        content = guide_file.read_text(encoding='utf-8')
                        guides[guide_file.name] = content
                    except Exception as e:
                        print(f"  ⚠️  Could not read guide {guide_file.name}: {e}")
                        
            except Exception as e:
                print(f"  ⚠️  Failed to process guides/index.json: {e}")

        # 增强 reference 文件
        self.enhance_reference(skill_dir=skill_dir)

        # 拼接 references 内容为文本
        references_text = "\n\n".join([
            f"# {filename}\n\n{content}" 
            for filename, content in references.items()
        ])
        
        # 从 references 内容提取bash脚本到 scripts/ 目录
        bash_extractor = BashExtractor(callback_config=self.callback_config)
        bash_extractor.extract_scripts_from_references(skill_dir, references_text)
        
        # 调用 PyScriptEnhancer 生成 scripts/ 目录下的脚本使用说明
        script_enhancer = PyScriptEnhancer(callback_config=self.callback_config)
        script_enhancer.enhance_scripts(skill_dir)

        # Read current SKILL.md
        current_skill_md = None
        if skill_md_path.exists():
            current_skill_md = skill_md_path.read_text(encoding='utf-8')
            print(f"  ℹ Found existing SKILL.md ({len(current_skill_md)} chars)")
        else:
            print(f"  ℹ No existing SKILL.md, will create new one")

        # Read scripts references.md
        scripts_references = None
        scripts_references_path = skill_dir / "references.md"
        if scripts_references_path.exists():
            scripts_references = scripts_references_path.read_text(encoding='utf-8')
            print(f"  ℹ Found existing scripts references.md ({len(scripts_references)} chars)")
        else:
            print(f"  ℹ No existing scripts references.md")

        # Build enhancement prompt
        prompt, meta_data_format = self._build_enhancement_prompt(
            skill_dir.name,
            references,
            current_skill_md,
            scripts_references,
            skill_dir,
            guides
        )

        print("\n🤖 Asking DeepSeek to enhance SKILL.md...")
        print(f"   Input: {len(prompt):,} characters")

        # 调用 LLM，传入 callbacks 用于 Langfuse 观测，生成技能主体内容
        try:
            message = self.llm.invoke(
                [{
                    "role": "user",
                    "content": prompt
                }],
                config=self.callback_config if self.callback_config else None
            )
            skill_body = message.content.strip()
            print(f"  ✓ Generated skill body content ({len(skill_body)} chars)")
            
            # 移除可能的元数据部分（如果模型返回了）
            yaml_pattern = r"^---\n(.*?)\n---"
            skill_body = re.sub(yaml_pattern, "", skill_body, flags=re.DOTALL | re.MULTILINE).strip()
            
        except Exception as e:
            print(f"❌ Error calling DeepSeek API: {e}")
            return False
        
        if not skill_body:
            print(f"❌ Failed to generate valid skill body content")
            return False
        
        # 使用大模型生成元数据
        print("\n📝 Generating metadata...")
        if not meta_data_format:
            print("  ⚠️  未找到元数据格式模板，无法生成元数据")
            return False
        
        meta_data = extract_meta_data(
            skill_body,
            meta_data_format,
            callback_config=self.callback_config if self.callback_config else None,
            skill_name=skill_dir.name
        )
        
        if not meta_data:
            print("  ❌ Failed to generate metadata")
            return False
        
        print(f"  ✓ Generated metadata ({len(meta_data)} chars)")
        
        # 拼接元数据和技能内容
        enhanced_content = f"""---
{meta_data}
---

{skill_body}
"""

        # 验证最终格式
        if not validate_skill_format(enhanced_content):
            print("  ⚠️  Final format validation failed")
            return False
        
        print(f"  ✓ Format validation passed\n")

        # Save enhanced version
        skill_md_path.write_text(enhanced_content, encoding='utf-8')
        print(f"  ✅ Saved enhanced SKILL.md")

        return True

    def _read_reference_files(self, references_dir: Path, max_chars: int = 200000) -> Dict[str, str]:
        """
        Read reference markdown files from skill directory.

        Args:
            references_dir: Path to references directory
            max_chars: Maximum total characters to read

        Returns:
            Dictionary mapping filename to content
        """
        if not references_dir.exists():
            return {}

        references = {}
        total_chars = 0

        # Read all .md files
        for ref_file in sorted(references_dir.glob("*.md")):
            if total_chars >= max_chars:
                break

            try:
                content = ref_file.read_text(encoding='utf-8')
                # Limit individual file size
                if len(content) > 30000:
                    content = content[:30000] + "\n\n...(truncated)"

                references[ref_file.name] = content
                total_chars += len(content)

            except Exception as e:
                print(f"  ⚠️  Could not read {ref_file.name}: {e}")

        return references

    def _build_enhancement_prompt(
        self,
        skill_name: str,
        references: Dict[str, str],
        current_skill_md: str = None,
        scripts_references: str = None,
        skill_dir: Path = None,
        guides: Dict[str, str] = None,
    ) -> tuple:
        """
        Build DeepSeek API prompt for enhancement.

        Args:
            skill_name: Name of the skill
            references: Dictionary of reference content
            current_skill_md: Existing SKILL.md content (optional)
            scripts_references: Existing references.md content (optional)
            skill_dir: Path to skill directory (optional)
            guides: Dictionary of guides content (optional)

        Returns:
            Tuple of (enhancement prompt, meta_data_format)
        """
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        # Collect file paths from references/, scripts/, and guides/ directories
        reference_files = []
        script_files = []
        guide_files = []
        
        if skill_dir:
            references_dir = skill_dir / "references"
            if references_dir.exists():
                for ref_file in sorted(references_dir.rglob("*")):
                    if ref_file.is_file() and not ref_file.name.startswith('.'):
                        rel_path = ref_file.relative_to(skill_dir)
                        reference_files.append(str(rel_path).replace('\\', '/'))
            
            scripts_dir = skill_dir / "scripts"
            if scripts_dir.exists():
                for script_file in sorted(scripts_dir.rglob("*")):
                    if script_file.is_file() and not script_file.name.startswith('.'):
                        rel_path = script_file.relative_to(skill_dir)
                        script_files.append(str(rel_path).replace('\\', '/'))
            
            guides_dir = skill_dir / "guides"
            if guides_dir.exists():
                for guide_file in sorted(guides_dir.rglob("*")):
                    if guide_file.is_file() and not guide_file.name.startswith('.') and guide_file.suffix == '.md':
                        rel_path = guide_file.relative_to(skill_dir)
                        guide_files.append(str(rel_path).replace('\\', '/'))
        
        # Build file paths section
        file_paths_section = ""
        if reference_files or script_files or guide_files:
            file_paths_section = "\nAVAILABLE FILES:\n"
            if reference_files:
                file_paths_section += "\nReferences directory files:\n"
                for ref_path in reference_files:
                    file_paths_section += f"- {ref_path}\n"
            if script_files:
                file_paths_section += "\nScripts directory files:\n"
                for script_path in script_files:
                    file_paths_section += f"- {script_path}\n"
            if guide_files:
                file_paths_section += "\nGuides directory files:\n"
                for guide_path in guide_files:
                    if guide_path.endswith('.md'):
                        file_paths_section += f"- {guide_path}\n"
            file_paths_section += "\n"
        
        # Build script references note
        script_refs_note = ""
        if scripts_references:
            script_refs_note = "\nNote: The script usage documentation is located at ./references.md (脚本使用说明文档)"
    
        prompt = f"""You are enhancing a skill's SKILL.md file. This skill is about: {skill_name}

I've scraped documentation and organized it into reference files. Your job is to create an EXCELLENT SKILL.md that will help Claude use this documentation effectively.

CURRENT TIME: {timestamp}
CURRENT SKILL.MD:
{'```markdown' if current_skill_md else '(none - create from scratch)'}
{current_skill_md or 'No existing SKILL.md'}
{'```' if current_skill_md else ''}

SCRIPTS REFERENCES.MD:
{'```markdown' if scripts_references else '(none - create from scratch)'}
{scripts_references or 'No existing references.md'}
{'```' if scripts_references else ''}
{script_refs_note}

{file_paths_section}
REFERENCE DOCUMENTATION:
"""

        for filename, content in references.items():
            prompt += f"\n\n## {filename}\n```markdown\n{content[:30000]}\n```\n"

        # Add guides section if guides exist
        if guides and len(guides) > 0:
            prompt += "\n\nUSER OPERATION GUIDES (用户操作指引):\n"
            for filename, content in guides.items():
                prompt += f"\n\n## {filename}\n```markdown\n{content[:30000]}\n```\n"

        # 加载技能模板文件
        template_content = None
        meta_data_format = ""
        try:
            workspace_dir = os.getenv('SKILL_WORKSPACE_DIR')
            if not workspace_dir:
                raise ValueError("环境变量 SKILL_WORKSPACE_DIR 未设置")
            template_path = os.path.join(workspace_dir, "template", "skill_name", "SKILL.md.example")
            # 检查文件是否存在
            template_path_obj = Path(template_path)
            if not template_path_obj.exists():
                raise FileNotFoundError(f"技能模板文件不存在: {template_path}")
            
            with open(template_path, "r", encoding="utf-8") as f:
                template_content = f.read()
            
            # 提取 YAML 前置区作为元数据格式模板
            yaml_pattern = r"^---\n(.*?)\n---"
            yaml_match = re.search(yaml_pattern, template_content, re.DOTALL | re.MULTILINE)
            if yaml_match:
                meta_data_format = yaml_match.group(1).strip()
            
            # 移除 YAML 前置区（---包裹部分），只保留主体内容
            template_body = re.sub(yaml_pattern, "", template_content, flags=re.DOTALL | re.MULTILINE).strip()
            
            prompt += f"""
SKILL 模板文件参考：
```markdown
{template_body}
```

"""
        except FileNotFoundError as e:
            # 模板文件不存在时抛出异常
            raise FileNotFoundError(f"技能模板文件不存在，无法继续: {e}") from e
        except Exception as e:
            # 其他错误也抛出异常
            raise RuntimeError(f"加载技能模板文件时发生错误: {e}") from e

        # 根据是否有模板文件内容构建不同的任务说明
        if template_content:
            print("  ✓ 已加载技能模板文件，将参考模板文件结构创建 SKILL.md")
            # 有模板文件时，参考模板文件内容和任务说明构建提示词
            prompt += """
你的任务：
参考上面的 SKILL 模板文件，创建一个增强的 SKILL.md，包含以下内容：

1. **清晰的"何时使用此技能"部分** - 明确说明触发条件
2. **详细的参考文件描述** - 说明每个参考文件中的内容
3. **实用的"使用此技能"部分** - 为用户提供清晰的使用指南
4. **核心概念部分**（如适用） - 解释核心概念
5. **Scripts README.MD** - 需要根据scripts readme.md的内容更新Executable Scripts相关的描述，并更新脚本工具的使用说明

重要提示：
- 严格按照上面的 SKILL 模板文件的结构和格式进行创建
- 从参考文档中提取真实的示例，不要编造
- 使其可操作且实用，对于明确提及特定的版本故障，应当精确描述版本信息（不要用例如、类似等描述或者缩短版本号），并有版本确认操作指令
- 对于特定版本故障，则非该版本匹配的故障不可使用本SKILL
- 对于偶现故障不需要确认现象
- 不要过于冗长 - 简洁但有用
- 保持 Claude 技能的 markdown 结构
- 使用正确的语言标签格式化代码示例
- 正文描述采用中文

输出要求：
- 仅返回 SKILL.md 的主体内容（不包含 YAML 前置元数据）
- 内容应该以 `# [技能名称]` 开始
- 不要包含 `---` 包裹的元数据部分
"""

        return prompt, meta_data_format