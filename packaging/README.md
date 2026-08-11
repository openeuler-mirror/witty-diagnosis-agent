# Witty Diagnosis Agent — RPM 打包与使用手册

面向 openEuler / CentOS / Fedora 等 RPM 系发行版，提供 `dnf install` 一键安装能力。

> 本次打包**不含 web 子系统**。原因见文末「打包范围」。

---

## 目录

- [一、文件说明](#一文件说明)
- [二、打包](#二打包在有网的-linux-构建机上)
- [三、安装](#三安装目标-linux-机器)
- [四、日常使用](#四日常使用)
- [五、升级与卸载](#五升级与卸载)
- [六、故障排查](#六故障排查)
- [七、打包范围与设计说明](#七打包范围与设计说明)

---

## 一、文件说明

本目录新增 4 个文件，**未修改任何现有项目代码**：

| 文件 | 作用 |
|---|---|
| `witty-diagnosis-agent.spec` | RPM 构建说明书（核心） |
| `witty-diagnosis-agent.sh` | 安装到 `/usr/bin` 的 wrapper 脚本 |
| `build-rpm.sh` | 一键打包脚本 |
| `README.md` | 本手册 |

### 安装后的文件布局

```
/usr/lib/witty-diagnosis-agent/         程序私有目录（用户不直接接触）
├── dist/                               插件入口 + CLI + MCP server + 提示词
├── skills/                             49 个诊断技能包
├── src/xiaoO/                          xiaoO 目标资源
└── package.json                        包根路标（不可省略，见第七节）

/usr/bin/witty-diagnosis-agent          用户唯一接触的命令入口

/usr/share/doc/witty-diagnosis-agent/   README、LICENSE、配置 schema
```

---

## 二、打包（在有网的 Linux 构建机上）

> ⚠️ **RPM 无法在 macOS 上构建。** 若你在 Mac 上开发，请用 2.4 的容器方式。

### 2.1 前置环境

```bash
sudo dnf install -y rpm-build rpmdevtools nodejs npm git tar
```

确认 Node.js ≥ 20（`package.json` 的硬性要求）：

```bash
node -v
```

### 2.2 一键打包

```bash
bash packaging/build-rpm.sh
```

脚本会自动完成：环境检查 → 打包源码 → 准备 `~/rpmbuild` 目录树 → 执行 `rpmbuild`。

产物位于 `~/rpmbuild/RPMS/noarch/`，形如：

```
witty-diagnosis-agent-0.10.0-1.beta.oe2403.noarch.rpm
```

### 2.3 离线构建

默认模式在 `%build` 阶段执行 `npm ci`，**需要构建机有网络**。

若构建机无网（或需提交 openEuler 官方源，要求严格离线），使用 vendor 模式：

```bash
bash packaging/build-rpm.sh --vendor
```

首次执行时脚本会联网生成 `~/rpmbuild/SOURCES/witty-node-modules-0.10.0.tar.gz`，之后即可完全离线复用。

### 2.4 容器打包（macOS 开发者推荐）

在项目根目录执行：

```bash
docker run --rm -v "$PWD":/src -w /src openeuler/openeuler:24.03 bash -c "dnf install -y rpm-build rpmdevtools nodejs npm git tar && bash packaging/build-rpm.sh && cp -r /root/rpmbuild/RPMS/noarch /src/rpm-out"
```

产物会落到项目下的 `rpm-out/` 目录。

> 产物为 `noarch`（无架构相关内容），**在任何架构上构建的包，x86_64 与 aarch64 通用**。Apple Silicon 上跑 x86 镜像会走模拟、速度较慢，但结果一致。

### 2.5 手动打包（理解每一步时使用）

```bash
rpmdev-setuptree
```

```bash
git archive --format=tar.gz --prefix=witty-diagnosis-agent-0.10.0/ -o ~/rpmbuild/SOURCES/witty-diagnosis-agent-0.10.0.tar.gz HEAD
```

```bash
cp packaging/witty-diagnosis-agent.spec ~/rpmbuild/SPECS/ && cp packaging/witty-diagnosis-agent.sh ~/rpmbuild/SOURCES/
```

```bash
rpmbuild -ba ~/rpmbuild/SPECS/witty-diagnosis-agent.spec
```

`-ba` 表示同时产出二进制包（RPMS）与源码包（SRPMS）。

---

## 三、安装（目标 Linux 机器）

安装分**两步**，缺一不可。

### 第 1 步：装包（root）

```bash
sudo dnf install ./witty-diagnosis-agent-0.10.0-1.beta.oe2403.noarch.rpm
```

> 用 `dnf install` 而非 `rpm -ivh`：dnf 会自动解决 nodejs / ansible 依赖，`rpm` 只会报错让你手动装。

**依赖说明：**

- 硬依赖 `nodejs >= 20`、`ansible` —— dnf 自动拉取
- 弱依赖（诊断工具）—— dnf 默认一并安装，装不上不阻塞：
  `strace` `perf` `gdb` `sysstat` `iproute` `smartmontools` `ipmitool` `tcpdump` `dmidecode` `ltrace` `numactl` `nvme-cli` `ethtool` `python3`
- **还需要 OpenCode 或 xiaoO**（至少一个），作为插件宿主，需自行安装

### 第 2 步：注册（普通用户，**不要用 sudo**）

```bash
witty-diagnosis-agent install
```

会交互式选择输出语言。跳过交互：

```bash
witty-diagnosis-agent install --language zh
```

这一步做的事：

- 把插件路径写入 `~/.config/opencode/opencode.json` 的 `plugin` 数组
- 将 `subagent_depth` 提升到 3（诊断流水线需要两层子代理委派）
- 生成 `~/.config/opencode/witty-diagnosis-agent.jsonc` 默认配置

该命令**幂等**，重复执行安全，并会自动清理旧版本遗留的路径条目。

> **为什么 RPM 不代劳？** RPM 由 root 执行，系统上可能有多个用户，root 不应也无法判断该往谁的家目录写配置。这是「系统装 + 用户配」类软件的标准做法。每个要使用的用户各自执行一次。

### 第 3 步：验证

```bash
witty-diagnosis-agent doctor
```

体检命令，报告插件注册状态、skills 可发现性与依赖完整性。

---

## 四、日常使用

启动宿主，插件自动加载：

```bash
opencode
```

修改配置：

```bash
vi ~/.config/opencode/witty-diagnosis-agent.jsonc
```

可用配置项完整说明见：

```bash
cat /usr/share/doc/witty-diagnosis-agent/witty-diagnosis-agent.schema.json
```

常用项：`output_language`（zh/en）、`disabled_agents`、`orchestration.max_parallel_subagents`、`guards.md_only`。

---

## 五、升级与卸载

### 升级

```bash
sudo dnf upgrade ./witty-diagnosis-agent-0.11.0-1.oe2403.noarch.rpm
```

安装路径不变时无需重新注册；保险起见可重跑一次 `witty-diagnosis-agent install`。

### 卸载

```bash
sudo dnf remove witty-diagnosis-agent
```

**只删系统文件**，保留 `~/.config/opencode/` 与 `~/.witty-diagnosis-agent/`（RPM 惯例：包管理器不删用户数据）。

彻底清理：

```bash
rm -rf ~/.witty-diagnosis-agent ~/.config/opencode/witty-diagnosis-agent.jsonc
```

并手工编辑 `~/.config/opencode/opencode.json`，删除 `plugin` 数组中指向 `/usr/lib/witty-diagnosis-agent/dist/index.js` 的条目。

---

## 六、故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `command not found` | 包未装成功 | `rpm -q witty-diagnosis-agent` 确认 |
| 装完但 OpenCode 无诊断能力 | **漏了第 2 步注册** | 执行 `witty-diagnosis-agent install` |
| 提示找不到 skills | 包根定位失败 | 确认 `/usr/lib/witty-diagnosis-agent/package.json` 存在 |
| 配置写进了 root 家目录 | 注册时误用 sudo | 切回普通用户重新执行 |
| 技能报「命令未找到」 | 弱依赖未安装 | 按第三节补装对应诊断工具 |
| 构建时 `npm ci` 失败 | 构建机无网络 | 改用 `build-rpm.sh --vendor` |
| 构建报 Node 版本过低 | Node < 20 | 升级 Node.js |

查看包内文件清单：

```bash
rpm -ql witty-diagnosis-agent
```

---

## 七、打包范围与设计说明

### 包含

`dist/`（插件入口、CLI、神农检索 MCP server、提示词）、`skills/`（49 个技能）、`src/xiaoO/`、`package.json`、README、LICENSE、配置 schema。

安装体积约 8 MB。

### 排除

- **web 子系统**（`src/witty/web/`）—— 依赖 `better-sqlite3`（原生模块，会破坏 noarch 通用性）、`mysql2`、fastify，且以 `tsx` 直跑 TS 源码、engines 限制 `node <24`，与主插件是两套独立系统。后续如需另出 `witty-diagnosis-agent-web` 子包。
- `skill-gen/third_party/Skill_Seekers`（git 子模块，开发期工具）
- `test/`、`smoke/`、`node_modules/`

### 三个关键设计点

**1. 为什么不打包 `node_modules`？**

tsup 将全部 9 个运行时依赖 bundle 进 `dist/`，且均为纯 JS（`zod`/`commander`/`marked`/`@clack/prompts` 等），无原生扩展。因此产物仅 496K，且可声明 `BuildArch: noarch`，x86_64 与 aarch64 通用 —— 无需逐个 npm 包做 RPM。

**2. 为什么 `package.json` 必须安装？**

`src/witty/shared/paths.ts` 的 `packageRootDir()` 通过「向上最多 6 层查找 package.json」来定位包根；配置 schema 中 `skills_dir` 默认值为相对路径 `"skills"`，由 `resolveSkillsDir()` 拼接包根得到。

缺失该文件时会回退到 `process.cwd()`，导致技能库定位失败。安装后的解析链：

```
/usr/lib/witty-diagnosis-agent/dist/cli.js
  ↑ 向上找到 package.json
/usr/lib/witty-diagnosis-agent/          ← 包根
  → 拼接 "skills"
/usr/lib/witty-diagnosis-agent/skills/   ← 正确定位
```

**这正是「无需修改任何代码」的前提** —— 现有路径解析逻辑在 FHS 布局下天然可用。

**3. 为什么用 wrapper 而非软链接？**

`dist/cli.js` 自带 `#!/usr/bin/env node`，理论上软链接可行。但软链接场景下 `import.meta.url` 在部分 Node 版本会解析到链接自身，干扰上述包根查找。wrapper 使用真实绝对路径 exec，规避此类边界问题。

### 未复用 `install.sh` 的原因

项目根目录的 `install.sh` 不适用于 RPM 场景：它会执行 `npm install` + `npm run build`（RPM 构建期禁止此类操作），且强制要求 TTY（无 TTY 时直接退出）。RPM 的 `%install` 段独立实现文件布局，注册环节则复用已有的 `witty-diagnosis-agent install` 子命令。
