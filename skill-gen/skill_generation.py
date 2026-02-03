import uuid
import os
import asyncio
import sys
import pathlib
import time
import json
from typing import Any, Dict, List, Tuple, Optional
from rich.console import Console
from rich.prompt import Prompt
from rich.progress import (
    Progress,
    SpinnerColumn,
    TextColumn,
    BarColumn,
    TaskProgressColumn,
)
from langfuse.langchain import CallbackHandler

sys.path.append(os.path.join(os.path.dirname(__file__), 'third_party', 'Skill_Seekers', 'src'))
from skill_seekers.cli.md_scraper import MarkdownToSkillConverter
from skill_seekers.cli.pdf_scraper import PDFToSkillConverter
from skill_name_gen import (
    gen_skill_name_from_text,
    agen_skill_name_from_text,
)
from markdown_formatter import md_formatter
from deepseek_skill_adapter import DeepSeekAdaptor
from html_extractor import run_html_extractor



def skill_seekers_gen(user_case_file, skill_name):
    # 检查 Langfuse 环境变量是否配置，如果未配置则禁用追踪
    langfuse_public_key = os.getenv('LANGFUSE_PUBLIC_KEY')
    langfuse_secret_key = os.getenv('LANGFUSE_SECRET_KEY')
    langfuse_enabled = bool(langfuse_public_key and langfuse_secret_key)
    
    if not langfuse_enabled:
        # 禁用 Langfuse 追踪,避免出现 401 错误
        os.environ['LANGFUSE_TRACING_ENABLED'] = 'False'
    
    # 检查 CUSTOM_SKILL_PATHS 环境变量是否设置
    custom_skill_paths = os.getenv('CUSTOM_SKILL_PATHS')
    if not custom_skill_paths:
        print("❌ 错误: 环境变量 CUSTOM_SKILL_PATHS 未设置，请先设置该环境变量")
        return False
    
    # 如果路径不存在，则创建目录
    if not os.path.exists(custom_skill_paths):
        os.makedirs(custom_skill_paths, exist_ok=True)
        print(f"📁 已创建目录: {custom_skill_paths}")

    skill_dir = os.path.join(custom_skill_paths, skill_name)

    if user_case_file.endswith(".pdf"):
        # 处理pdf文件
        config = {
            'name': skill_name,  # skill的名称，用于标识和命名生成的skill
            'pdf_path': user_case_file,  # PDF文件的完整路径，需要提取内容的源文件
            'save_dir': custom_skill_paths,  # skill保存的根目录路径，从环境变量获取
            'description': f'Use when referencing {skill_name} documentation',  # skill的描述信息，说明何时使用该skill
            'extract_options': {  # PDF内容提取的配置选项
                'chunk_size': 10,  # 文本分块大小，每块包含的页面数量
                'min_quality': 5.0,  # 内容质量的最小阈值，低于此值的内容会被过滤
                'extract_images': False,  # 是否从PDF中提取图片内容
                'min_image_size': 100  # 提取图片的最小尺寸（像素），小于此尺寸的图片会被忽略
            },
            'scripts_config': {  # 脚本提取和处理的配置选项
                'line_threshold': 30,  # 识别为脚本的最小行数阈值，超过此行数的代码块会被提取为脚本
                'min_quality_score': 6.0  # 脚本质量的最小分数阈值，低于此分数的脚本会被过滤
            }
        }
        # Create converter
        converter = PDFToSkillConverter(config)
        if not converter.extract_pdf():
            print(f"pdf文件提取失败：{config['pdf_path']}")
            return False

    elif user_case_file.endswith((".md", ".markdown")):
        # 处理markdown文件
        # 使用文件路径接口，而不是文本内容接口
        config = {
            'name': skill_name,  # skill的名称，用于标识和命名生成的skill
            'md_path': user_case_file,  # Markdown文件的完整路径，需要提取内容的源文件
            'save_dir': custom_skill_paths,  # skill保存的根目录路径，从环境变量获取
            'description': f'Use when referencing {skill_name} documentation',  # skill的描述信息，说明何时使用该skill
            'scripts_config': {  # 脚本提取和处理的配置选项
                'line_threshold': 30,  # 识别为脚本的最小行数阈值，超过此行数的代码块会被提取为脚本
                'min_quality_score': 6.0,  # 脚本质量的最小分数阈值，低于此分数的脚本会被过滤
                'max_display_lines': 5  # 在 reference 中显示的最大行数，超过则显示简化格式
            }
        }
        # Create converter
        converter = MarkdownToSkillConverter(config)
        # 使用文件路径接口提取
        if not converter.extract_markdown():
            print(f"❌ Markdown 文件提取失败：{user_case_file}")
            return False

    elif user_case_file.endswith(".txt"):
        
        print(f"📖 读取 TXT 文件: {user_case_file}")
        
        # 读取txt文件内容
        with open(user_case_file, 'r', encoding='utf-8') as f:
            txt_content = f.read()
        print(f"✅ 已读取文件内容，共 {len(txt_content)} 个字符")
        
        # 创建 Langfuse handler 用于格式化过程
        if langfuse_enabled:
            try:
                langfuse_handler = CallbackHandler()
                trace_id = str(uuid.uuid4())
                callback_config = {
                    "callbacks": [langfuse_handler],
                    "configurable": {
                        "thread_id": trace_id
                    },
                    "metadata": {
                        "langfuse_trace_name": f"txt_to_markdown_{skill_name}"
                    }
                }
            except Exception as e:
                print(f"⚠️  Failed to initialize Langfuse: {e}")
                callback_config = None
        else:
            # Langfuse 环境变量未配置，不创建 handler
            callback_config = None
        
        # 将txt内容转换为markdown格式
        print(f"🔄 正在将 TXT 格式转换为 Markdown 格式...")
        md_content = md_formatter(txt_content, callback_config=callback_config)
        print(f"✅ 格式转换完成，Markdown 内容共 {len(md_content)} 个字符")
        
        # 使用转换后的markdown内容调用md_scraper
        config = {
            'name': skill_name,  # skill的名称，用于标识和命名生成的skill
            'save_dir': custom_skill_paths,  # skill保存的根目录路径，从环境变量获取
            'description': f'Use when referencing {skill_name} documentation',  # skill的描述信息，说明何时使用该skill
            'scripts_config': {  # 脚本提取和处理的配置选项
                'line_threshold': 30,  # 识别为脚本的最小行数阈值，超过此行数的代码块会被提取为脚本
                'min_quality_score': 6.0,  # 脚本质量的最小分数阈值，低于此分数的脚本会被过滤
                'max_display_lines': 5  # 在 reference 中显示的最大行数，超过则显示简化格式
            }
        }
        # Create converter
        converter = MarkdownToSkillConverter(config)
        # 使用文本内容接口传入转换后的markdown
        if not converter.extract_markdown(md_content=md_content):
            print(f"❌ Markdown 内容提取失败")
            return False

    elif user_case_file.startswith(("http://", "https://")):
        # 处理 URL
        print(f"🌐 读取 URL: {user_case_file}")
        
        # 创建 Langfuse handler 用于 URL 抓取过程
        if langfuse_enabled:
            try:
                langfuse_handler = CallbackHandler()
                trace_id = str(uuid.uuid4())
                callback_config = {
                    "callbacks": [langfuse_handler],
                    "configurable": {
                        "thread_id": trace_id
                    },
                    "metadata": {
                        "langfuse_trace_name": f"url_to_markdown_{skill_name or 'auto'}"
                    }
                }
            except Exception as e:
                print(f"⚠️  Failed to initialize Langfuse: {e}")
                callback_config = None
        else:
            # Langfuse 环境变量未配置，不创建 handler
            callback_config = None
        
        # 使用 html_extractor 抓取 URL 并转为 markdown
        print(f"🔄 正在抓取 URL 内容并转换为 Markdown 格式...")
        try:
            result = asyncio.run(run_html_extractor(user_case_file, callback_config=callback_config))
            md_content = result.get("markdown", "")
            extracted_skill_name = result.get("skill_name", "").strip()
            
            if not md_content:
                print(f"❌ 未能从 URL 获取有效内容（可能被安全拦截或页面为空）")
                return False
            
            print(f"✅ URL 内容抓取完成，Markdown 内容共 {len(md_content)} 个字符")
            
            # 处理 skill_name：如果提取到了 skill_name 且用户没有提供，则使用提取的
            if extracted_skill_name and (not skill_name or not skill_name.strip()):
                skill_name = extracted_skill_name
                skill_dir = os.path.join(custom_skill_paths, skill_name)
                print(f"✅ 未提供技能名称，使用从 URL 提取的技能名称: {skill_name}")

            # 使用转换后的markdown内容调用md_scraper
            config = {
                'name': skill_name,  # skill的名称，用于标识和命名生成的skill
                'save_dir': custom_skill_paths,  # skill保存的根目录路径，从环境变量获取
                'description': f'Use when referencing {skill_name} documentation',  # skill的描述信息，说明何时使用该skill
                'scripts_config': {  # 脚本提取和处理的配置选项
                    'line_threshold': 30,  # 识别为脚本的最小行数阈值，超过此行数的代码块会被提取为脚本
                    'min_quality_score': 6.0,  # 脚本质量的最小分数阈值，低于此分数的脚本会被过滤
                    'max_display_lines': 5  # 在 reference 中显示的最大行数，超过则显示简化格式
                }
            }
            # Create converter
            converter = MarkdownToSkillConverter(config)
            # 使用文本内容接口传入转换后的markdown
            if not converter.extract_markdown(md_content=md_content):
                print(f"❌ Markdown 内容提取失败")
                return False
        except Exception as e:
            print(f"❌ URL 抓取失败: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
            return False

    else:
        raise NotImplementedError(f"暂不支持的文件格式: {user_case_file}，当前支持 PDF、Markdown、TXT 和 Html 格式")

    # Build 构建基础skill
    converter.build_skill()

    # 创建 Langfuse handler（用于观测 LLM 调用）
    if langfuse_enabled:
        try:
            langfuse_handler = CallbackHandler()
            print("📊 Langfuse observability initialized")
            # 创建 adaptor（传入 callbacks）
            trace_id = str(uuid.uuid4())
            callback_config = {
                "callbacks":[langfuse_handler],
                "configurable": {
                    "thread_id": trace_id
                },
                "metadata": {
                    "langfuse_trace_name": f"skill_generation_{skill_name}"
                }
            }
        except Exception as e:
            print(f"⚠️  Failed to initialize Langfuse: {e}")
            print("   Continuing without observability...")
            callback_config = None
    else:
        # Langfuse 环境变量未配置，不创建 handler
        print("ℹ️  Langfuse environment variables not configured, skipping observability")
        callback_config = None

    
    adaptor = DeepSeekAdaptor(callback_config=callback_config)

    if not adaptor.supports_enhancement():
        print(f"❌ Error: {adaptor.PLATFORM_NAME} does not support AI enhancement")
    # Get API key
    api_key = os.environ.get(adaptor.get_env_var_name(), '').strip()
    if not api_key:
        print(f"❌ Error: {adaptor.get_env_var_name()} not set")

    success = adaptor.enhance(pathlib.Path(skill_dir), api_key)

    if success:
        print(f"\n✅ skill生成完成，开始清理中间结果")
        skill_path = pathlib.Path(skill_dir)

        try:
            adaptor.cleanup_intermediate_files(skill_path)
            print("✅ 中间结果清理完成")
        except Exception as e:
            print(f"❌ Error cleaning intermediate files: {e}")
    else:
        print(f"❌ skill生成失败")
    return success


def _normalize_config_item(item: Any) -> Dict[str, str]:
    """
    将不同形式的配置统一成包含 pdf_path / skill_name 的 dict。

    支持两种 JSON 结构：
    1. 列表：
       [
         {"pdf_path": "test_case/kubernetes_ops_guide.pdf", "skill_name": "k8s_skill"},
         ...
       ]
    2. 映射：
       {
         "k8s_skill": "test_case/kubernetes_ops_guide.pdf",
         "oom_skill": "test_case/OOM相关参数配置与原因排查_常见问题_Huawei Cloud EulerOS-华为云.pdf"
       }
    """
    if isinstance(item, dict):
        # 正常结构：{"pdf_path": "...", "skill_name": "..."}
        if "pdf_path" in item and "skill_name" in item:
            return {
                "pdf_path": str(item["pdf_path"]),
                "skill_name": str(item["skill_name"]),
            }

        # 兜底：如果 dict 只有一对 key/value，当成 {skill_name: pdf_path}
        if len(item) == 1:
            skill_name, pdf_path = next(iter(item.items()))
            return {"pdf_path": str(pdf_path), "skill_name": str(skill_name)}

    raise ValueError(f"无效的配置项: {item}")


def _load_batch_config(config_path: str) -> List[Dict[str, str]]:
    """
    从 JSON 文件中读取批量配置。

    支持的 JSON 格式：
    1. 列表格式：
       [
         {"pdf_path": "path/to/file.pdf", "skill_name": "skill_name"},
         ...
       ]
    2. 字典格式（推荐，如 batch_pdf.json）：
       {
         "skill_name1": "path/to/file1.pdf",
         "skill_name2": "path/to/file2.pdf"
       }
    """
    if not os.path.isfile(config_path):
        raise FileNotFoundError(f"配置文件不存在: {config_path}")

    with open(config_path, "r", encoding="utf-8") as f:
        raw = json.load(f)

    items: List[Dict[str, str]] = []

    # 结构 1：列表格式
    if isinstance(raw, list):
        for entry in raw:
            items.append(_normalize_config_item(entry))
        return items

    # 结构 2：字典格式 {skill_name: pdf_path}（如 batch_pdf.json）
    if isinstance(raw, dict):
        for skill_name, pdf_path in raw.items():
            # 直接构建标准化格式，无需再调用 _normalize_config_item
            items.append(
                {
                    "pdf_path": str(pdf_path),
                    "skill_name": str(skill_name),
                }
            )
        return items

    raise ValueError("配置 JSON 需为列表或对象，请检查文件格式。")


async def _build_entries_from_dir(root_path: str) -> List[Dict[str, str]]:
    """
    当用户传入的是目录时：
    - 递归扫描目录下所有 PDF 文件
    - 统计数量并询问用户是否全部转换为 skill
    - 若确认，则为每个 PDF 自动生成 skill name（异步并发）
    """
    console = Console()
    abs_root = os.path.abspath(root_path)

    if not os.path.isdir(abs_root):
        console.print(f"[bold red]目录不存在: {root_path}[/bold red]")
        return []

    pdf_files: List[str] = []
    for dirpath, _, filenames in os.walk(abs_root):
        for filename in filenames:
            if filename.lower().endswith(".pdf"):
                pdf_files.append(os.path.join(dirpath, filename))

    if not pdf_files:
        console.print(
            f"[bold yellow]目录中未找到任何 PDF 文件: {abs_root}[/bold yellow]"
        )
        return []

    console.print("\n[bold cyan]扫描到以下 PDF 文件：[/bold cyan]")
    for idx, pdf_path in enumerate(sorted(pdf_files), 1):
        console.print(f"  {idx}. {pdf_path}")

    console.print(
        f"\n[bold magenta]共发现 {len(pdf_files)} 个 PDF 文件。[/bold magenta]"
    )
    choice = Prompt.ask(
        "[bold cyan]是否将以上所有 PDF 转换为 skill？(y/n)[/bold cyan]",
        choices=["y", "n", "Y", "N"],
        default="n",
    ).lower()

    if choice != "y":
        console.print("[bold yellow]已取消批量处理。[/bold yellow]")
        return []

    console.print("[bold cyan]开始为每个 PDF 自动生成 skill name（异步并发）…[/bold cyan]")

    async def _gen_skill_name_for_pdf(pdf_path: str) -> Dict[str, str]:
        """为单个 PDF 生成 skill name"""
        base_name = os.path.splitext(os.path.basename(pdf_path))[0]
        try:
            skill_name = await agen_skill_name_from_text(base_name)
        except Exception:
            # 兜底：简单清洗文件名
            safe_name = base_name.strip().lower().replace(" ", "-")
            skill_name = safe_name or "skill"

        entry = {
            "pdf_path": pdf_path,
            "skill_name": skill_name,
        }
        console.print(
            f"[green]生成 skill 名称[/green]: [bold]{skill_name}[/bold] "
            f"← {pdf_path}"
        )
        return entry

    # 异步并发处理所有 PDF 文件
    tasks = [_gen_skill_name_for_pdf(pdf_path) for pdf_path in sorted(pdf_files)]
    entries = await asyncio.gather(*tasks)

    console.print(
        f"[bold green]✅ 已为 {len(entries)} 个 PDF 生成 skill name。[/bold green]"
    )
    return entries


async def _process_one(
    entry: Dict[str, str], 
    semaphore: asyncio.Semaphore
) -> Tuple[bool, str, str, Optional[str]]:
    """
    处理单个 PDF → skill 任务，使用线程池封装同步代码，实现整体异步。
    
    Returns:
        Tuple[bool, str, str, Optional[str]]: 
            (是否成功, skill_name, pdf_path, 错误信息)
    """
    console = Console()
    pdf_path = entry["pdf_path"]
    skill_name = entry["skill_name"]

    if not pdf_path.lower().endswith(".pdf"):
        error_msg = f"跳过非 PDF 文件: {pdf_path}"
        console.print(
            f"[bold yellow]跳过非 PDF 文件: {pdf_path} (skill: {skill_name})[/bold yellow]"
        )
        return False, skill_name, pdf_path, error_msg

    if not os.path.isfile(pdf_path):
        error_msg = f"PDF 文件不存在: {pdf_path}"
        console.print(
            f"[bold red]PDF 文件不存在，已跳过: {pdf_path} (skill: {skill_name})[/bold red]"
        )
        return False, skill_name, pdf_path, error_msg

    async with semaphore:
        console.print(
            f"[bold cyan]开始生成 skill[/bold cyan]: [green]{skill_name}[/green] "
            f"← {pdf_path}"
        )
        try:
            # skill_seekers_gen 是同步函数，用 to_thread 包装，使其在异步环境下运行
            result = await asyncio.to_thread(
                skill_seekers_gen,
                user_case_file=pdf_path,
                skill_name=skill_name,
            )
            if not result:
                error_msg = "skill_seekers_gen 返回 False，生成失败"
                console.print(
                    f"[bold red]❌ skill 生成失败[/bold red]: {skill_name}, "
                    f"pdf: {pdf_path}, error: {error_msg}"
                )
                return False, skill_name, pdf_path, error_msg
            console.print(
                f"[bold green]✅ skill 生成完成[/bold green]: {skill_name}"
            )
            return True, skill_name, pdf_path, None
        except Exception as e:
            error_msg = str(e)
            console.print(
                f"[bold red]❌ skill 生成失败[/bold red]: {skill_name}, "
                f"pdf: {pdf_path}, error: {e}"
            )
            return False, skill_name, pdf_path, error_msg


async def batch_generate_from_config(
    config_path: str,
    concurrency: int = 3,
) -> None:
    """
    依据 JSON 配置文件，批量从 PDF 生成 skill。

    :param config_path: JSON 配置文件路径，或包含 PDF 的目录路径
    :param concurrency: 最大并发任务数
    """
    console = Console()
    # 支持两种输入：
    # 1. JSON 配置文件（原有逻辑）
    # 2. 目录路径：自动扫描目录下所有 PDF，并为其生成 skill name
    if os.path.isdir(config_path):
        console.print(
            f"[bold cyan]检测到目录输入，将扫描目录下的 PDF 文件：[/bold cyan]{config_path}"
        )
        entries = await _build_entries_from_dir(config_path)
    else:
        entries = _load_batch_config(config_path)

    if not entries:
        console.print("[bold yellow]未发现需要处理的任务。[/bold yellow]")
        return

    semaphore = asyncio.Semaphore(concurrency)

    console.print(
        f"[bold magenta]共读取到 {len(entries)} 个 PDF → skill 任务，"
        f"并发数: {concurrency}[/bold magenta]"
    )

    tasks = [
        _process_one(entry, semaphore)
        for entry in entries
    ]

    # 收集结果
    results: List[Tuple[bool, str, str, Optional[str]]] = []
    
    # 增强的进度展示
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TaskProgressColumn(),
        console=console,
        transient=True,
    ) as progress:
        task_id = progress.add_task(
            description="批量生成 skill 中...",
            total=len(tasks),
        )

        for coro in asyncio.as_completed(tasks):
            result = await coro
            results.append(result)
            progress.update(task_id, advance=1)

    # 统计成功和失败
    success_count = sum(1 for success, _, _, _ in results if success)
    failure_count = len(results) - success_count
    failed_items = [
        (skill_name, pdf_path, error_msg)
        for success, skill_name, pdf_path, error_msg in results
        if not success
    ]

    # 输出统计报告
    console.print("\n" + "=" * 60)
    console.print("[bold cyan]📊 批量处理统计报告[/bold cyan]")
    console.print("=" * 60)
    console.print(f"[bold green]✅ 成功: {success_count} 个[/bold green]")
    console.print(f"[bold red]❌ 失败: {failure_count} 个[/bold red]")
    console.print(f"[bold]📝 总计: {len(results)} 个[/bold]")
    
    if failed_items:
        console.print("\n[bold red]失败的文件列表:[/bold red]")
        for idx, (skill_name, pdf_path, error_msg) in enumerate(failed_items, 1):
            console.print(
                f"  {idx}. [yellow]Skill:[/yellow] {skill_name}\n"
                f"     [yellow]PDF:[/yellow] {pdf_path}\n"
                f"     [yellow]错误:[/yellow] {error_msg}"
            )
    
    console.print("=" * 60)
    
    if failure_count == 0:
        console.print("[bold green]🎉 所有任务处理完成！[/bold green]")
    else:
        console.print(
            f"[bold yellow]⚠️  处理完成，但有 {failure_count} 个任务失败，请检查上述失败列表。[/bold yellow]"
        )


def run_skill_generation(
    input_path: str,
    output_path: Optional[str] = None,
    concurrency: int = 3,
    skill_name: Optional[str] = None,
) -> None:
    """
    统一入口函数，供外部（如 app.py）调用：

    - 如果 input_path 是单个案例文档路径（pdf/txt/markdown），则进行单个 skill 生成
    - 如果 input_path 是 JSON 配置文件路径或目录路径，则调度批量处理
    
    :param input_path: 输入路径（案例文档或批量配置路径）
    :param output_path: 输出目录路径，如果提供则设置 CUSTOM_SKILL_PATHS 环境变量
    :param concurrency: 批量生成时的并发数，默认为 3
    :param skill_name: skill 名称，如果提供则使用该名称，否则交互式获取或自动生成
    """
    console = Console()

    # 如果提供了 output_path，设置环境变量
    if output_path:
        os.environ['CUSTOM_SKILL_PATHS'] = output_path
        console.print(f"[bold cyan]输出目录设置为:[/bold cyan] {output_path}")

    # 单文件模式：既不是目录，也不是 .json，当作单个案例文档处理
    # 支持文件路径和 URL
    is_file = os.path.isfile(input_path) and not input_path.lower().endswith(".json")
    is_url = input_path.startswith(("http://", "https://"))
    
    if is_file or is_url:
        user_case_file = input_path

        # 获取/生成 skill 名称
        if skill_name:
            # 使用提供的 skill 名称
            console.print(
                f"[bold green]使用提供的 skill 名称：[/bold green]{skill_name}"
            )
        else:
            if is_url:
                # URL 模式：提示将从 URL 中提取技能名称
                console.print(
                    "[bold yellow]未提供 skill 名称，将从 URL 内容中自动提取技能名称…[/bold yellow]"
                )
                # URL 模式下，skill_name 将在 skill_seekers_gen 中从 URL 内容提取
                # 这里先设置为空字符串，让 skill_seekers_gen 处理
                skill_name = ""
            else:
                # 文件模式：自动生成 skill 名称
                console.print(
                    "[bold yellow]未提供 skill 名称，将根据案例文档名称自动生成名称…[/bold yellow]"
                )
                # 使用文件路径作为输入文本，由大模型提取关键信息生成 name
                skill_name = gen_skill_name_from_text(user_case_file)
                console.print(
                    f"[bold green]自动生成的 skill 名称为：[/bold green]{skill_name}"
                )

        print("========== 开始基于案例文档生成Skill ============")
        start_time = time.time()

        try:
            skill_seekers_gen(user_case_file=user_case_file, skill_name=skill_name)
        finally:
            end_time = time.time()
            elapsed_time = end_time - start_time
            print(
                f"========== 完成Skill生成任务 (耗时: {elapsed_time:.2f}秒) ============"
            )
    else:
        # 批量模式：目录或 JSON 配置文件
        concurrency = max(1, concurrency)

        console.print(
            f"[bold cyan]使用路径[/bold cyan]: {input_path}  "
            f"[bold cyan]并发数[/bold cyan]: {concurrency}"
        )

        asyncio.run(
            batch_generate_from_config(input_path, concurrency=concurrency)
        )
