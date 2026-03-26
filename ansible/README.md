## Ansible 集成约定（Dayu / Fuxi / Kuafu）

> 本目录用于存放与智能诊断系统配套的 Ansible 配置（inventory 模板等），便于 Kuafu 通过 `ansible` 统一在远程主机上执行诊断/Skill 脚本。

### 1. 目录结构约定

- `ansible/`
  - `README.md`：当前说明文件
  - `hosts.ini`：唯一 inventory 文件，所有主机组与认证均在此维护

### 2. Inventory 使用方式

- 文件路径：`ansible/hosts.ini`
- **组名规范**：仅使用**字母、数字、下划线**（勿用连字符 `-`），否则会触发 Ansible 的 `Invalid characters in group names` 并可能影响认证。
- **密码认证**：使用 `ansible_password` 时，控制机需安装 `sshpass`（如 `apt install sshpass` / `yum install sshpass`），否则会报 `Permission denied (password)`。
- 使用方式：

```bash
# 对指定组做连通性检查（组名用下划线，如 session_cache_server）
ansible -i ansible/hosts.ini session_cache_server -m ping
```

Dayu / Fuxi 在构造 `[Fault Context]` 的 `Access` 字段时，应优先使用 **主机组名**（例如 `openeuler`），Kuafu 会在执行时结合实际使用的 `-i` 参数。

### 3. 利用现有 Skill 脚本执行远程诊断

以 `openeuler-docker-hang` Skill 提供的脚本为例：

- 本地脚本路径：`.witty-diagnosis-agent/skills/openeuler-docker-hang/scripts/check_kernel_printk.sh`
- 推荐通过 Ansible `script` 模块在目标主机上执行：

```bash
# 在 openeuler 组的所有主机上执行 check_kernel_printk.sh
ansible -i ansible/hosts.ini openeuler \
  -m script -a ".witty-diagnosis-agent/skills/openeuler-docker-hang/scripts/check_kernel_printk.sh"
```

在 Kuafu 的执行逻辑中，建议优先使用上述 `script` 或 `copy + shell` 组合方式：

- 使用 `script`：一次性传输并执行脚本，适合只读/采集类 Skill。
- 使用 `copy + shell`：
  - 将脚本复制到统一目录（如 `/tmp/witty-skills/{skill_name}`）；
  - `shell` 模块赋权并执行；
  - 执行完成后删除临时脚本，避免堆积。

### 4. 推荐实践

- **命名约定**：主机组名仅用字母、数字、下划线（如 `session_cache_server`），与 Fuxi/Dayu 的 Access 保持一致。
- **最小权限**：Ansible 账号应只具备诊断/采集所需的只读或最低写权限。

