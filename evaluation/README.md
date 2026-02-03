**Skills 评估工具使用指南**

本指南介绍如何对已有 skills 进行评估：

- 本地评估工具：`evaluate_skill.py`
- 将 skills 上传到 Langfuse 数据集：`upload_skills_langfuse.py`
- 从 Langfuse 拉取数据集并评估：`evaluate_skill_from_langfuse.py`

---

**前置准备**

1. **准备 `.env`**

参考根目录下的示例文件：

```bash
cp .env.example .env
```

然后根据不同场景需要编辑 `.env`。

---

**一、本地评估 Skill**

文件：evaluate_skill.py

该脚本会自动读取指定文件夹 `EVALUATION_SKILL_PATH` 下的 skill，对每一个被评估的 skill 生成一个报告，并把报告写入文件（`EVALUATION_REPORT_DIR` 下，文件名形如：`<skill_name>_YYYYMMDD_HHMMSS.txt`）。

报告内容包括 Skill 综合评估平均分和各维度详细评分与理由

**1. Skill 目录结构要求**

每个 Skill 目录至少包含：

- `SKILL.md` 或 `skill.md`
- 可选：`references/` 目录，用于放参考文档（md 文件等）
- 可选：`scripts/` 目录，用于放参考代码

典型结构示例：

```text
evaluation/skills/oom_skill/
  ├── SKILL.md
  ├── references/
  │   ├── ref1.md
  │   └── ref2.md
  └── scripts/
      ├── script1.sh
      └── script2.py
```

**2. 环境变量配置**

在 `.env` 中设置：

- `DEEPSEEK_API_KEY`
- `EVALUATION_SKILL_PATH`  
  - 可以是：
    - 单个 Skill 目录：`.../evaluation/skills/oom_skill`
    - 包含多个 Skill 的父目录：`.../evaluation/skills`
- `EVALUATION_REPORT_DIR`
- `EVALUATION_MAX_WORKERS`（可选，默认 4）

**3. 运行方式**

在项目根目录执行：

```bash
cd evaluation
python evaluate_skill.py
```

---

**二、构建 Langfuse skills 数据集**

文件：upload_skills_langfuse.py

该脚本会自动在 `EVALUATION_SKILL_PATH` 下查找所有的有效 skills，
- 对每个 Skill：
  - 构建 `manifest`（文件列表、大小、修改时间等 meta 信息）。
  - 读取 `SKILL.md` 全文（最长 80,000 字符）。
  - 从 `reference/` 或 `references/` 下收集 `.md` 文件内容（带截断）。
  - 从 `scripts/` 下收集脚本内容（带截断）。
  - 组装为一个 `input` 字典：

    ```python
    {
        "skill_name": ...,
        "skill_md": ...,
        "references": {...},
        "scripts": {...},
        "manifest": {...},
    }
    ```

并将这些 skill 上传至  `EVALUATION_LANGFUSE_DATASET_NAME` 构建数据集。

上传完成后，Langfuse 中对应 dataset 将包含每个 Skill 对应的一条 item，`input` 就是后续评估工具使用的来源数据。

**1. 环境变量配置**

在 `.env` 中配置：

- `LANGFUSE_PUBLIC_KEY`
- `LANGFUSE_SECRET_KEY`
- `LANGFUSE_HOST`（如非默认）
- `EVALUATION_LANGFUSE_DATASET_NAME`  
  - 要上传到的 Langfuse dataset 名称（不存在会尝试自动创建）
- `EVALUATION_SKILLS_ROOT`  
  - 本地技能根目录：
    - 如果此目录下有 `SKILL.md`，则认为它本身就是一个 Skill 目录；
    - 否则，会遍历其子目录，寻找含 `SKILL.md` 的目录。

**2. 运行方式**

在项目根目录执行：

```bash
cd evaluation
python upload_skills_langfuse.py
```

---

**三、从 Langfuse 拉取数据并评估**

文件：evaluate_skill_from_langfuse.py

该脚本用于从 Langfuse 的某个 dataset 拉取数据，对每个 item 进行评估，最后把评估结果写回到 Langfuse 中。评估逻辑与本地评估完全一致。评估结果会写回到 Langfuse，同时也会保存一份到本地 `EVALUATION_REPORT_DIR`（文件名形如：`<skill_name>_YYYYMMDD_HHMMSS.txt`）

最终，你可以：

- 在本地 `EVALUATION_REPORT_DIR` 中看到每个 Skill 的评估报告；
- 在 Langfuse 控制台中查看：
  - `scores`（各维度分数 + 平均分）
  - `output` 字段中的完整文本报告。

**1. 环境变量配置**

在 `.env` 中配置：

- DeepSeek：
  - `DEEPSEEK_API_KEY`
- Langfuse：
  - `LANGFUSE_PUBLIC_KEY`
  - `LANGFUSE_SECRET_KEY`
  - `LANGFUSE_HOST`
- 评估报告保存路径：
  - `EVALUATION_REPORT_DIR`
- Langfuse 数据集配置：
  - `LANGFUSE_DATASET_NAME`：要从哪个 dataset 拉取待评估 skills 数据（应与上传时使用的一致或兼容）
  - `EVALUATION_LANGFUSE_DATASET_LIMIT`（可选）：限制每次评估的 item 数量，如 `5`；空则不限制

**2. 运行方式**

在项目根目录执行：

```bash
cd evaluation
python evaluate_skill_from_langfuse.py
```