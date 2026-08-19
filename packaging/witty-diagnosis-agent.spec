# witty-diagnosis-agent.spec
#
# 打包范围：OpenCode/xiaoO 插件本体（dist/）、诊断技能库（skills/）、
#           xiaoO 资源（src/xiaoO/）。
# 不含 web 子系统：src/witty/web 依赖 better-sqlite3（原生模块，会破坏
#           noarch）、mysql2、fastify，且用 tsx 直跑 TS 源码、engines 限制
#           node <24，与主插件是两套东西，后续如需另出子包。
#
# 离线构建：默认 %build 阶段执行 npm ci，需要构建机有网络。
#           如需严格离线（例如提交 openEuler 官方源），预先生成 vendor 包：
#               npm ci && tar czf witty-node-modules-%%{version}.tar.gz node_modules
#           放入 SOURCES/，然后带 --with vendor 构建：
#               rpmbuild -ba --with vendor witty-diagnosis-agent.spec

%bcond_with vendor
%bcond_with strictdeps

# 本包分发的是已 bundle 的 JS 与数据文件，无需以下自动处理
%global debug_package %{nil}
%global __brp_mangle_shebangs %{nil}
%global __brp_check_rpaths %{nil}

# 安装根目录：程序私有文件，用户不直接接触
%global wittydir %{_prefix}/lib/%{name}

Name:           witty-diagnosis-agent
Version:        0.10.0
Release:        2.beta%{?dist}
Summary:        Witty Diagnosis Agent - AI-powered Linux fault diagnosis for OpenCode
Summary(zh_CN): Witty 智能诊断 Agent —— 面向 OpenCode 的 Linux 故障诊断插件

License:        MulanPSL-2.0
URL:            https://gitcode.com/openeuler/witty-diagnosis-agent
Source0:        %{name}-%{version}.tar.gz
Source1:        %{name}.sh
%if %{with vendor}
Source2:        witty-node-modules-%{version}.tar.gz
%endif

# 产物是纯 JS 与数据文件，x86_64 / aarch64 通用
BuildArch:      noarch

# 构建期需要 node/npm，但同样常来自 NodeSource / nvm（不在 rpm 库内）。
# 默认不声明，改由 build-rpm.sh 在构建前实际检查 node -v；
# 如需恢复标准声明（例如提交官方源），带 --with strictdeps 构建。
%if %{with strictdeps}
BuildRequires:  nodejs >= 20
BuildRequires:  npm
%endif

# Node.js 与 Ansible 是运行必需，但故意不写成 Requires：
# 实践中二者常经由 NodeSource / nvm / pip 安装，不在 rpm 数据库内，
# 写死 Requires 会让这些机器根本装不上包。改为弱依赖 + 运行时检查：
#   - dnf 默认仍会尝试从源里安装
#   - 已用其他方式装好的机器不受阻
#   - 真正缺失时，wrapper 与 doctor 会给出明确提示
Recommends:     nodejs >= 20
Recommends:     ansible

# 弱依赖：技能脚本按需调用的诊断工具。dnf 默认会一并安装，
# 但缺失时不阻塞本包安装（不同场景用不到全部工具）。
Recommends:     strace
Recommends:     perf
Recommends:     gdb
Recommends:     sysstat
Recommends:     iproute
Recommends:     smartmontools
Recommends:     ipmitool
Recommends:     tcpdump
Recommends:     dmidecode
Recommends:     ltrace
Recommends:     numactl
Recommends:     nvme-cli
Recommends:     ethtool
Recommends:     python3

%description
Witty Diagnosis Agent is an AI-powered fault diagnosis plugin for OpenCode
and xiaoO, built on the hypothetico-deductive troubleshooting paradigm and a
multi-agent collaborative architecture.

It ships 48 diagnosis skills covering CPU, memory, disk, network, filesystem,
kernel and hardware faults, providing automated root-cause analysis with
read-only diagnosis phases and user-approved remediation.

Note: this package installs system files only. Each user must run
"witty-diagnosis-agent install" once to register the plugin into their own
OpenCode configuration.

%description -l zh_CN
Witty 智能诊断 Agent 基于「假设-验证」故障排查范式与 Multi-Agent 协同架构，
为 OpenCode / xiaoO 提供分钟级、代码行级的全自动故障诊断能力。

内置 48 个诊断技能，覆盖 CPU、内存、磁盘、网络、文件系统、内核与硬件故障，
诊断阶段严格只读，修复阶段需用户审批确认。

注意：本包只安装系统文件。每个使用者需自行执行一次
"witty-diagnosis-agent install" 将插件注册到自己的 OpenCode 配置中。

%prep
%setup -q
%if %{with vendor}
# 离线模式：展开预先准备好的 node_modules
tar xzf %{SOURCE2}
%endif

%build
%if %{with vendor}
# 离线模式：依赖已就位，跳过安装
echo "vendor mode: 使用预置 node_modules"
%else
# 联网模式：按 lockfile 精确安装（lockfileVersion 3）
npm ci
%endif

# tsup 打 ESM bundle（依赖全部内联进 dist/），并生成 JSON Schema
npm run build

# 构建产物自检：缺任一入口都说明构建失败，及早退出而不是打出坏包
test -f dist/index.js           || { echo "构建失败：缺少 dist/index.js" >&2; exit 1; }
test -f dist/cli.js             || { echo "构建失败：缺少 dist/cli.js" >&2; exit 1; }
test -f dist/case-search-cli.js || { echo "构建失败：缺少 dist/case-search-cli.js" >&2; exit 1; }
test -d dist/prompts            || { echo "构建失败：缺少 dist/prompts/" >&2; exit 1; }

# 冒烟自检：本包不分发 node_modules，产物必须能在没有依赖树的情况下启动。
# tsup 默认把 dependencies 当 external，一旦 tsup.config.ts 的 noExternal
# 被改动，产物会在用户机器上以 ERR_MODULE_NOT_FOUND 启动失败——而文件
# 齐全，上面的 test -f 全部通过。故在此真正跑一次。
smoke=$(mktemp -d)
cp -a dist package.json "$smoke"/
(
  cd "$smoke"
  node dist/cli.js --help >/dev/null 2>"$smoke"/err || {
    echo "构建失败：dist/cli.js 脱离 node_modules 无法启动" >&2
    head -5 "$smoke"/err >&2
    exit 1
  }
  node -e 'import("./dist/index.js").catch(e=>{console.error(e.message);process.exit(1)})' \
    >/dev/null 2>"$smoke"/err2 || {
    echo "构建失败：dist/index.js 脱离 node_modules 无法加载" >&2
    head -5 "$smoke"/err2 >&2
    exit 1
  }
) || exit 1
rm -rf "$smoke"

%install
rm -rf %{buildroot}

install -d %{buildroot}%{wittydir}
install -d %{buildroot}%{_bindir}
install -d %{buildroot}%{_docdir}/%{name}

# 1) 构建产物：插件入口 + CLI + MCP server + 提示词
cp -a dist %{buildroot}%{wittydir}/

# 2) 诊断技能库（约 6.8M，47 个常规技能 + 1 个门控技能）
cp -a skills %{buildroot}%{wittydir}/
# 门控技能（默认不暴露，需 CASE_KB_ID 才启用）单独成目录，使 skills/ 可整体软链
cp -a skills-gated %{buildroot}%{wittydir}/

# 3) xiaoO 目标所需资源（command / tools / config）
install -d %{buildroot}%{wittydir}/src
cp -a src/xiaoO %{buildroot}%{wittydir}/src/

# 4) package.json —— 必须安装，不可省略。
#    shared/paths.ts 的 packageRootDir() 靠「向上查找 package.json」定位包根，
#    schema 里 skills_dir 默认值是相对路径 "skills"，需由包根拼接。
#    缺此文件将回退到 process.cwd()，导致 skills 定位失败。
install -m 0644 package.json %{buildroot}%{wittydir}/package.json

# 5) /usr/bin 下的 wrapper
install -m 0755 %{SOURCE1} %{buildroot}%{_bindir}/%{name}

# 6) 文档与配置 schema（供用户查阅可用配置项）
install -m 0644 README.md   %{buildroot}%{_docdir}/%{name}/README.md
install -m 0644 LICENSE     %{buildroot}%{_docdir}/%{name}/LICENSE
install -m 0644 assets/%{name}.schema.json %{buildroot}%{_docdir}/%{name}/%{name}.schema.json

# 技能脚本保持可执行位，供技能调用
find %{buildroot}%{wittydir}/skills %{buildroot}%{wittydir}/skills-gated -type f -name "*.sh" -exec chmod 0755 {} \;
find %{buildroot}%{wittydir}/skills %{buildroot}%{wittydir}/skills-gated -type f -name "*.py" -exec chmod 0755 {} \;

# 清理开发期残留
find %{buildroot}%{wittydir} -name ".DS_Store" -delete

%files
%license LICENSE
%dir %{wittydir}
%{wittydir}/dist
%{wittydir}/skills
%{wittydir}/skills-gated
%{wittydir}/src
%{wittydir}/package.json
%{_bindir}/%{name}
%dir %{_docdir}/%{name}
%doc %{_docdir}/%{name}/README.md
%doc %{_docdir}/%{name}/%{name}.schema.json
%{_docdir}/%{name}/LICENSE

%post
cat <<'EOF'
====================================================
  Witty Diagnosis Agent 已安装到系统目录。

  还差一步：每个使用者需在自己的账号下（不要用 sudo）
  执行一次注册命令，把插件写入个人 OpenCode 配置：

      witty-diagnosis-agent install

  随后可用体检命令验证：

      witty-diagnosis-agent doctor

  前提：系统中已安装 OpenCode 或 xiaoO。
====================================================
EOF

%postun
if [ $1 -eq 0 ]; then
cat <<'EOF'
====================================================
  witty-diagnosis-agent 系统文件已移除。

  用户级配置与数据按 RPM 惯例保留，如需彻底清理请手动执行：

      rm -rf ~/.witty-diagnosis-agent
      rm -f  ~/.config/opencode/witty-diagnosis-agent.jsonc

  并编辑 ~/.config/opencode/opencode.json，
  删除 plugin 数组中指向 /usr/lib/witty-diagnosis-agent 的条目。
====================================================
EOF
fi

%changelog
* Wed Aug 19 2026 witty-diagnosis-agent <witty@openeuler.org> - 0.10.0-2.beta
- 技能目录拆分：门控技能移入 skills-gated/，使 skills/ 可整体软链
- 修复插件换 checkout 后技能仍加载旧仓库的问题
- 技能脚本可执行位覆盖 skills-gated/

* Tue Aug 11 2026 witty-diagnosis-agent <witty@openeuler.org> - 0.10.0-1.beta
- 首个 RPM 打包版本
- 包含插件本体、CLI、神农检索 MCP server 与 49 个诊断技能
- 暂不包含 web 子系统
