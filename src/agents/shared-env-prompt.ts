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
    try {
      const hostsConfig = await fs.promises.readFile(hostsFile, "utf8");
      if (hostsConfig.trim()) {
        extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，内容如下：\n\`\`\`ini\n${hostsConfig.trim()}\n\`\`\`\n`;
      } else {
        extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，但内容为空。\n`;
      }
    } catch (e) {
      extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，但读取失败。\n`;
    }
  } else {
    extraPrompt += `- **Ansible Inventory**: 配置文件不存在 (\`${hostsFile}\`)。\n`;
  }

  extraPrompt += "\n**注意：如果上述预检查信息显示 Ansible 已安装，或 inventory 配置文件已存在，请直接使用上述信息，切勿再反复调用 bash 探测。**\n";

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

  return extraPrompt;
}
