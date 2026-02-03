## 测试用例说明

### 目录结构

```
test_case/
├── kubernetes_ops_guide.pdf                          # Kubernetes 运维指南，包含长脚本代码
├── OOM相关参数配置与原因排查_常见问题_Huawei Cloud EulerOS-华为云.pdf  # OOM 故障案例文档
├── productdesc-hce-pdf.pdf                           # 产品描述文档，包含多个故障案例
└── README.md                                         # 测试用例说明文档
```

### 📝使用示例

本项目的程序入口为`app.py`。假设你想要使用测试用例生成 Skill：

- 首先，运行如下命令，执行Skill生成程序
```Bash
python app.py
```
- 然后，根据提示输入测试用例PDF文件的完整路径，例如：`test_case/kubernetes_ops_guide.pdf`
  
- 执行后，程序将处理文本并将其生成的 Skill 文件保存至你配置的 `CUSTOM_SKILL_PATHS` 目录中。

- 最后，可以打开`CUSTOM_SKILL_PATHS`中生成的结果进行查看，确认生成的效果

### 测试用例

本目录包含用于测试 skill 生成功能的测试用例，根据不同的测试目标分为三种类型：

### 1. kubernetes_ops_guide.pdf

**用途**：测试带长脚本的 skill 生成，长脚本生成目录为`your_skills/scripts/`

**测试重点**：
- 评估文档中提取脚本的质量
- 评估调用函数生成结果

**说明**：这类 PDF 文档包含较长的脚本代码，用于测试系统从文档中准确提取脚本代码的能力，以及生成的调用函数是否符合预期。

### 2. OOM相关参数配置与原因排查_常见问题_Huawei Cloud EulerOS-华为云.pdf

**用途**：测试单个故障案例的 skill 生成

**测试重点**：
- 评估长文本分割到 `your_skills/references/` 目录的结果

**说明**：这类 PDF 文档包含单个故障案例的详细描述，用于测试系统将长文本内容合理分割并保存到 `references/` 目录的效果。

### 3. productdesc-hce-pdf.pdf

**用途**：测试包含多个故障案例的 skill 生成

**测试重点**：
- 评估故障章节切分效果

**说明**：这类 PDF 文档包含多个故障案例，用于测试系统如何识别和切分不同的故障章节，确保每个故障案例被正确分离和处理。