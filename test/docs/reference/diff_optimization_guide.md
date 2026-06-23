# 差分火焰图分析增强 — 优化说明

## 优化了什么

### 1. 模板数据变量化

**修改文件**：`templates/flamegraph-diff-analysis.html`

**修改内容**：将模板中所有硬编码数据替换为 `{{VARIABLE}}` 占位符

| 硬编码数据 | 变量名 | 行号 |
|-----------|--------|:----:|
| `v2.14.0 · 7d3f1a`（基线版本） | `{{BASELINE_VERSION}}` | 265 |
| `v2.15.0 · b91c4e`（当前版本） | `{{CURRENT_VERSION}}` | 267 |
| `CPU · on-CPU 采样`（事件类型） | `{{EVENT_TYPE}}` | 270 |
| `99 Hz · 30 秒窗口`（采样信息） | `{{SAMPLING_INFO}}` | 271 |
| `api-gateway / request-handler`（服务名） | `{{SERVICE_NAME}}` | 338 |
| 图例文字 | `{{LEGEND_TEXT}}` | 311 |
| **43 个树节点 + 86 个样本数** | `{{PROFILE_TREE}}` | 361-401 |

**为什么要这样优化**：
- 原模板的火焰图数据（43 个函数节点、基线/当前各 86 个样本数）是硬编码在 JS 中的
- 每次分析不同数据都需要手动修改 HTML，不可维护
- 抽取为变量后，`diff_report_generator.py` 可以自动注入数据

### 2. 新增差分分析总结段落

**修改文件**：`templates/flamegraph-diff-analysis.html`

**新增内容**：在"性能剖析概览"和"主要性能回退"之间插入"差异分析总结"区块

```html
<div class="pblock">
  <h3>差异分析总结</h3>
  <p><b>整体趋势：</b>{{SUMMARY_TREND}}</p>
  <p><b>主要回退：</b>{{SUMMARY_REGRESSION}}</p>
  <p><b>主要改善：</b>{{SUMMARY_IMPROVEMENT}}</p>
  <p><b>根因分析：</b>{{SUMMARY_ROOT_CAUSE}}</p>
</div>
```

| 变量 | 生成逻辑 |
|------|---------|
| `{{SUMMARY_TREND}}` | 基线 vs 当前总采样数对比（增加/减少/持平） |
| `{{SUMMARY_REGRESSION}}` | delta > 0 的前 5 项回退 |
| `{{SUMMARY_IMPROVEMENT}}` | delta < 0 的前 5 项改善 |
| `{{SUMMARY_ROOT_CAUSE}}` | 前 3 项回退的函数名和 delta 值 |

**为什么要这样优化**：
- 原模板有"性能剖析概览"（显示总采样数）和"主要性能回退/改善"（排行榜），但缺少文本形式的**整体分析结论**
- 用户需要一眼看出：整体趋势是变好还是变差、主要问题在哪、改善在哪
- 这 4 段总结由 `diff_report_generator.py` 自动生成，无需人工编写

### 3. 创建差分报告生成器

**新增文件**：`scripts/render/diff_report_generator.py`

**流程**：

```
baseline.folded + target.folded
         │
         ▼
    diff_analysis.py（计算差异）
         │
         ├── 基线 1629 栈, 169 采样
         ├── 目标 106 栈, 200 采样
         ├── 差异项: 50 条
         │
         ▼
    build_tree()（构建差分 profile tree）
         │
         ▼
    generate_summary()（生成 4 段总结文本）
         │
         ▼
    注入模板: {{BASELINE_VERSION}} → "基线文件名"
              {{PROFILE_TREE}} → JSON 树
              {{SUMMARY_TREND}} → "增加了 31 采样"
              ...
         │
         ▼
    输出: diff_report.html（55KB）
```

**为什么要这样优化**：
- 原模板只能展示硬编码的示例数据，没有实际分析能力
- `diff_report_generator.py` 对接了已有的 `diff.py` 分析引擎
- 支持任意两个 folded 文件的差分对比，自动生成完整 HTML 报告

### 4. 差分分析功能实现

**复用现有组件**：

| 组件 | 功能 | 来源 |
|------|------|------|
| `parse_folded()` | 解析 folded 格式 | `analyzers/diff.py` |
| `diff_analysis()` | 计算栈级差异（delta、pct_diff） | `analyzers/diff.py` |
| `flamegraph-diff-analysis.html` | 差分可视化模板 | `templates/` |
| `diff_report_generator.py` | 串联以上组件生成报告 | **新增** |

---

## 测试验证

```bash
python diff_report_generator.py \
  "FlameGraph/test/results/perf-funcab-cmd-01-collapsed-all.txt" \
  "FlameGraph/test/results/perf-iperf-stacks-pidtid-01-collapsed-all.txt" \
  --output diff_test.html
```

**输出**：
```
Baseline: 2 stacks, 169 samples
Target:   106 stacks, 200 samples
Diff items: 50
Output: diff_test.html (55KB)
```

生成的 HTML 包含：
- 完整的差分火焰图可视化
- 基线/当前对比和 Δ 着色
- 性能回退/改善排行榜
- 差异分析总结段落（趋势 + 根因）

---

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `templates/flamegraph-diff-analysis.html` | 修改 | 硬编码数据 → `{{VAR}}` 占位符 |
| `templates/flamegraph-diff-analysis.html` | 修改 | 新增"差异分析总结"段落 |
| `scripts/render/diff_report_generator.py` | **新增** | 差分报告生成器 |
