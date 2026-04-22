import { exec } from "child_process"
import { promisify } from "util"
import * as fs from "fs"
import * as path from "path"
import * as os from "os"

const execAsync = promisify(exec)

export async function getSharedEnvPrompt(): Promise<string> {
  let extraPrompt = "\n\n# 环境预检查结果 (Pre-check Results)\n";
  extraPrompt += "在每次交互前，系统已自动探测了本地环境状态：\n";

  try {
    await execAsync("which ansible");
    extraPrompt += "- **Ansible**: 已安装 (Command exists).\n";
  } catch (e) {
    extraPrompt += "- **Ansible**: 未安装 (Command not found).\n";
  }

  const hostsFile = path.join(os.homedir(), ".witty-diagnosis-agent", "ansible", "hosts.ini");
  if (fs.existsSync(hostsFile)) {
    extraPrompt += `- **Ansible Inventory**: 配置文件路径存在 (\`${hostsFile}\`)。该路径信息仅供参考，表示这里保存过历史服务器记录；当前用户对应的目标服务器**不一定**在这个文件中，后续必须将用户本次输入与该路径对应的历史记录做比对，严禁仅凭该文件路径或历史记录直接认定连接信息已明确。\n`;
  } else {
    extraPrompt += `- **Ansible Inventory**: 配置文件不存在 (\`${hostsFile}\`)。\n`;
  }

  extraPrompt += "\n**注意：如果上述预检查信息显示 Ansible 已安装，或 inventory 路径已存在，可将其作为环境参考信息；但不得把它当成当前用户目标服务器已确认的证据，更不要读取其中历史内容替代用户输入。**\n";

  const currentTime = new Date().toISOString();
  extraPrompt += `\n# 当前系统时间\n当前时间为: ${currentTime}\n`;

  const wittyHomeDir = path.join(os.homedir(), ".witty-diagnosis-agent");
  extraPrompt += `\n# 用户工作目录\n当前 \`~/.witty-diagnosis-agent/\` 对应的绝对路径为: \`${wittyHomeDir}\`\n`;
  extraPrompt += `请在生成计划、草稿以及后续需要写文件的步骤中，严格使用该绝对路径代替 \`~\`。\n\n`;
  extraPrompt += `该目录下的树形结构如下，请直接使用，**不需要再去查询**：\n`;
  extraPrompt += `\`\`\`text\n`;
  extraPrompt += `${wittyHomeDir}\n`;
  extraPrompt += `├── ansible/\n`;
  extraPrompt += `│   └── hosts.ini\n`;
  extraPrompt += `├── fuxi/\n`;
  extraPrompt += `├── dayu/\n`;
  extraPrompt += `│   ├── plans/\n`;
  extraPrompt += `│   ├── drafts/\n`;
  extraPrompt += `│   └── report/\n`;
  extraPrompt += `├── kuafu/\n`;
  extraPrompt += `└── baize/\n`;
  extraPrompt += `    └── report/\n`;
  extraPrompt += `\`\`\`\n`;

  extraPrompt += `\n# 中间过程输出规范\n`;
  extraPrompt += `在任务执行过程中，**非最终结果的中间输出须严格遵循以下原则**：\n`;
  extraPrompt += `1. **不重复已知内容** — 不得复述用户已提供的输入信息、背景或已确认的结论。\n`;
  extraPrompt += `2. **只输出前瞻性内容** — 中间输出仅包含"当前步骤结论（一句话）+ 下一步计划"，省略推导过程、中间变量和冗余说明。\n`;
  extraPrompt += `3. **格式极简** — 优先使用单行或极短段落，禁止使用不必要的标题、列表嵌套或解释性铺垫。\n\n`;
  extraPrompt += `**中间输出模板：**\n`;
  extraPrompt += `\`\`\`\n`;
  extraPrompt += `✓ [当前步骤完成内容，一句话]\n`;
  extraPrompt += `→ 下一步：[具体行动]\n`;
  extraPrompt += `\`\`\`\n`;
  extraPrompt += `\n**注意：仅在最终结果时，才允许输出完整的无压缩的内容（如排查方案、分析报告等）。**\n`;

  extraPrompt += `\n# 输出文件路径规范 (Output File Path Specification)\n`;
  extraPrompt += `**重要：所有 Agent 协作时，必须在输出结果时明确标注输出文件的绝对路径。**\n\n`;
  extraPrompt += `1. **结果必须包含路径** — 每当生成文件（报告、计划、诊断结果等）时，必须在输出末尾明确标注：\n`;
  extraPrompt += `   📁 **输出文件路径**：`{绝对路径}`\n\n`;
  extraPrompt += `2. **路径必须是绝对路径** — 禁止使用 \`~\`、相对路径或通配符，必须给出完整绝对路径。\n\n`;
  extraPrompt += `3. **下游 Agent 引用规则** — 后续 Agent 读取前序产物时，必须引用前序输出的确切绝对路径，不得自行在目录中匹配查找。\n\n`;
  extraPrompt += `**输出格式示例：**\n`;
  extraPrompt += `\`\`\`\n`;
  extraPrompt += `## 诊断结果\n\n已完成 XX 诊断分析。\n\n📁 **输出文件路径**：\n- 诊断报告：`/Users/leiw/.witty-diagnosis-agent/dayu/report/xxx.md`\n- 原始数据：`/Users/leiw/.witty-diagnosis-agent/kuafu/xxx.json`\n\n下一步：交由 Baize 进行根因分析\n`;
  extraPrompt += `\`\`\`\n`;

  return extraPrompt;
}
