# Skill Generation 工具

我们提供了一个**Skill 生成工具**，用于从 PDF / Markdown / TXT / URL 等文档自动生成符合 Claude Skills 规范的技能包，并可对生成的技能进行统计与管理。

---

## 功能概览

- **文档 → Skill 自动生成**
  - 支持单文件：PDF / Markdown / TXT / URL
  - 支持目录 / JSON 批量配置
  - 自动调用第三方 `Skill_Seekers` 工具进行内容抽取与基础 Skill 构建
- **DeepSeek 增强**
  - 使用 DeepSeek 模型对生成的 Skill 进行增强：
    - 补全 / 优化 `SKILL.md`
    - 提取/生成脚本说明、指南文档等
- **Custom Skill 管理**
  - 基于环境变量 `CUSTOM_SKILL_PATHS` 的 custom skill 目录：
    - `--list`：列出所有 custom skills 及其关键词
    - `--list-keywords`：统计关键词在 custom skills 中的分布

---

## 运行方式

> 以下命令请在项目根目录下执行。

### 1. 安装依赖（推荐使用 uv）

```bash
# 进入项目根目录后执行
uv venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate

# 安装依赖
uv pip install -e .
```

### 2. 通过 app.py 启动 Skill Generation

```bash
# 查看帮助
python skill-gen/app.py --help

# 示例：从单个 PDF 生成 skill（skill 名称自动生成）
python skill-gen/app.py --input /path/to/document.pdf

# 示例：从单个 PDF 生成 skill，指定 skill 名称
python skill-gen/app.py --input /path/to/document.pdf --skill-name my-skill

# 示例：从目录批量生成 skill（扫描目录下所有 PDF）
python skill-gen/app.py --input /path/to/doc_dir/ --output /path/to/custom_skills

# 示例：从 JSON 配置批量生成
python skill-gen/app.py --input /path/to/batch_config.json --output /path/to/custom_skills --concurrency 5
```

#### CLI 参数说明

- `--input`（可选，缺省时会交互式询问）  
  - 单文件：`*.pdf` / `*.md` / `*.markdown` / `*.txt`
  - 目录：自动扫描目录中所有 PDF
  - URL：`http://` 或 `https://` 开头的链接
  - JSON：批量配置文件（具体格式见代码注释）
- `--output`  
  - 生成的 skills 输出目录  
  - 未指定时默认读取环境变量 `CUSTOM_SKILL_PATHS`
- `--concurrency`  
  - 批量生成时的最大并发数（默认 `3`）
- `--skill-name`  
  - 单文件模式下指定 Skill 名称  
  - 未提供时会自动生成或从 URL 内容中提取

当你省略 `--input` 时，程序会在命令行中提示你输入路径。

---

## Custom Skills 管理（列表 & 统计）

工具通过环境变量 `CUSTOM_SKILL_PATHS` 来定位 custom skills 根目录，每个子目录代表一个 skill，内部需要包含 `SKILL.md`。

### 1. 环境变量配置

建议在仓库根目录或 `skill-gen/` 目录下创建/编辑 `.env`：

```bash
# 示例 .env 配置
CUSTOM_SKILL_PATHS=/path/to/custom_skills
DEEPSEEK_API_KEY=sk-xxx
DEEPSEEK_MODEL=deepseek-chat
DEEPSEEK_BASE_URL=https://api.deepseek.com
```

> `app.py` 会在启动时加载 `.env`（通过 `dotenv.load_dotenv(override=True)`），并使用 `CUSTOM_SKILL_PATHS`：
> - 作为 `--output` 的默认值
> - 作为 `--list` / `--list-keywords` 的扫描根目录

### 2. 列出 Custom Skills

```bash
python skill-gen/app.py --list
```

说明：
- 若 **未配置** `CUSTOM_SKILL_PATHS`：  
  - 提示需要设置环境变量，并给出示例配置路径
- 若已配置但路径不存在 / 非目录：  
  - 打印当前值并提示路径无效
- 若目录存在但没有任何 skill：  
  - 提示「当前目录下暂无 skill（需包含 SKILL.md 的子目录）」  
  - 不会报错

### 3. 关键词统计

```bash
python skill-gen/app.py --list-keywords
```

- 仅针对 `CUSTOM_SKILL_PATHS` 下的 custom skills 进行统计
- 统计每个关键词对应多少个 skill，并以矩阵表的形式展示
- 对未配置 / 路径无效的情况有与 `--list` 相同的友好提示

---

## Skill 模板与增强逻辑

Skill 生成和增强依赖一个模板文件，用于指导 DeepSeek 生成最终的 `SKILL.md`：

- 模板路径由环境变量 `SKILL_WORKSPACE_DIR` 决定：
  - 默认由 `app.py` 设置为 `skill-gen` 目录：
    - `SKILL_WORKSPACE_DIR = skill-gen/`
- 模板文件实际路径：

```text
${SKILL_WORKSPACE_DIR}/template/skill_name/SKILL.md.example
```

本仓库已内置该模板文件：

```text
skill-gen/
  template/
    skill_name/
      SKILL.md.example
      references/README.md
      scripts/README.md
```

`deepseek_skill_adapter.py` 会：
- 读取上述模板
- 提取其中的 YAML frontmatter 作为元数据格式模板
- 使用模板正文作为结构参考，生成最终的 `SKILL.md` 内容

如需自定义模板，可：
1. 覆盖 `SKILL.md.example` 文件内容，或  
2. 设置 `SKILL_WORKSPACE_DIR` 到你自己的模板目录根路径。

---

## 第三方依赖说明

本工具在 `skill-gen/third_party/Skill_Seekers` 下集成了第三方项目 **Skill Seekers**，用于：
- PDF / Markdown 文本抽取与结构化
- 基础 Skill 目录结构的构建（`SKILL.md`、`references/` 等）

代码中仅通过 `sys.path.append(...third_party/Skill_Seekers/src)` 方式引入，不建议在本仓库直接修改第三方代码，如需定制行为，
优先在本目录（`skill-gen/`）增加适配层。

---

## 必要环境变量汇总

- **Skill & DeepSeek 相关**
  - `DEEPSEEK_API_KEY`：DeepSeek API Key（必需）
  - `DEEPSEEK_MODEL`：DeepSeek 模型名，例如 `deepseek-chat`
  - `DEEPSEEK_BASE_URL`：DeepSeek API Base URL
  - `CUSTOM_SKILL_PATHS`：custom skills 根目录（建议配置）
  - `SKILL_WORKSPACE_DIR`：Skill 模板工作区根目录（默认由 `app.py` 设置为 `skill-gen/`）

确保上述环境变量配置正确后，即可在当前项目中稳定使用 Skill Generation 工具。
